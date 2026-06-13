#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gerar_pesos.py

Gera, a partir de um classificador MNIST linear em TF/Keras, os arquivos VHDL
usados pelo núcleo de classificação MNIST:

  - mascaras_top64_pkg.vhd
  - bias_densos_pkg.vhd
  - rom_pesos_densos.vhd
  - pesos_quantizados_info.txt

Quando --salvar-modelo for usado, tambem salva artefatos software para o
trace_benchmark.py:

  - classificador_denso.keras
  - classificador_binario.npy

O classificador denso e o classificador binário top-64 usam critérios diferentes:

  - O classificador denso usa pesos quantizados int8 e bias:
        score_d = bias_d + soma Wq(pixel,d), para pixels ativos.

  - O classificador binário top-64 usa apenas contagem de presença:
        score_d = quantidade de pixels ativos dentro da máscara do dígito d.

  - As máscaras top-64 são geradas por heatmap discriminativo:
        para cada dígito d, calcula-se a frequência média de ativação de cada
        pixel naquele dígito e nos dígitos competidores. O score usado é:
        score_d(p) = freq_d(p) - penalidade * competidor_d(p).
        Os top-K pixels com maior score formam a máscara daquele dígito.

Convenções respeitadas pelo VHDL:

  - imagem_mnist_t tem 784 bits;
  - pixel i = linha*28 + coluna é acessado como imagem(i);
  - rom_pesos_densos.vhd contém uma ROM síncrona de 784 endereços úteis x 80 bits.

Uso típico, com os arquivos VHDL no mesmo diretório deste script:

  python gerar_pesos.py --epochs 25

Ou usando um modelo Keras já treinado, desde que ele tenha uma camada Dense com
pesos de formato (784, 10):

  python gerar_pesos.py --modelo modelo_mnist_linear.keras

Por padrão, os arquivos são escritos no mesmo diretório deste script. Para outro
local, use --saida-dir.

O hardware denso deste projeto implementa uma camada linear única sobre pixels
binarizados. Portanto, este script treina/espera um modelo linear Dense(10), sem
camadas ocultas, convoluções ou ativações intermediárias.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path
from typing import Tuple

import numpy as np
import tensorflow as tf

IMG_WIDTH_C = 28
IMG_HEIGHT_C = 28
IMG_BITS_C = IMG_WIDTH_C * IMG_HEIGHT_C
NUM_DIGITOS_C = 10
TOP_K_C = 64
DENSE_MODEL_FILENAME_C = "classificador_denso.keras"
BINARY_MODEL_FILENAME_C = "classificador_binario.npy"
TOP64_PENALIDADE_C = 0.1
TOP64_USAR_MAX_COMPETIDOR_C = False
PESO_WIDTH_C = 8
SCORE_DENSO_WIDTH_C = 20
ROM_DATA_WIDTH_C = NUM_DIGITOS_C * PESO_WIDTH_C
MNIST_INNER_SIZE_C = 20
INK_DETECT_THRESHOLD_C = 0.05

AUG_CANVAS_SIZE_C = 40
AUG_PROFILE_CONFIGS_C: dict[str, dict[str, float]] = {
    "leve": {
        "rotation_deg": 4.0,
        "scale_min": 0.9,
        "scale_max": 1.1,
        "thickness_prob": 0.1,
        "erode_prob": 0.20,
        "intensity_jitter": 0.10,
        "threshold_jitter": 0.05,
    },
    "medio": {
        "rotation_deg": 8.0,
        "scale_min": 0.85,
        "scale_max": 1.15,
        "thickness_prob": 0.3,
        "erode_prob": 0.45,
        "intensity_jitter": 0.12,
        "threshold_jitter": 0.07,
    },
    "forte": {
        "rotation_deg": 12.0,
        "scale_min": 0.8,
        "scale_max": 1.2,
        "thickness_prob": 0.50,
        "erode_prob": 0.50,
        "intensity_jitter": 0.15,
        "threshold_jitter": 0.10,
    },
}


# -----------------------------------------------------------------------------
# Utilidades gerais
# -----------------------------------------------------------------------------

def configurar_seed(tf, seed: int) -> None:
    np.random.seed(seed)
    try:
        tf.random.set_seed(seed)
    except Exception:
        pass


def binarizar_mnist(x: np.ndarray, threshold: float) -> np.ndarray:
    """Converte imagens MNIST uint8 0..255 para matriz float32 binária N x 784."""
    if not (0.0 <= threshold <= 1.0):
        raise ValueError("threshold deve estar entre 0.0 e 1.0")

    x_norm = x.astype(np.float32) / 255.0
    x_bin = (x_norm >= threshold).astype(np.float32)
    return x_bin.reshape((-1, IMG_BITS_C))


def carregar_mnist_bruto(tf):
    (x_train, y_train), (x_test, y_test) = tf.keras.datasets.mnist.load_data()
    return (
        x_train.astype(np.uint8),
        y_train.astype(np.int64),
        x_test.astype(np.uint8),
        y_test.astype(np.int64),
    )


def carregar_mnist(tf, threshold: float):
    x_train, y_train, x_test, y_test = carregar_mnist_bruto(tf)
    x_train_bin = binarizar_mnist(x_train, threshold)
    x_test_bin = binarizar_mnist(x_test, threshold)
    return x_train_bin, y_train, x_test_bin, y_test


def _normalizar_tinta(image: np.ndarray) -> np.ndarray:
    ink = image.astype(np.float32)
    if ink.size == 0:
        raise ValueError("imagem vazia")
    if float(np.max(ink)) > 1.0:
        ink = ink / 255.0
    return np.clip(ink, 0.0, 1.0)


def _resize_bilinear(image: np.ndarray, out_height: int, out_width: int) -> np.ndarray:
    if out_height <= 0 or out_width <= 0:
        raise ValueError("dimensoes de resize devem ser positivas")

    src = _normalizar_tinta(image)
    src_height, src_width = src.shape
    if src_height == out_height and src_width == out_width:
        return src.copy()

    y = (np.arange(out_height, dtype=np.float32) + 0.5) * src_height / out_height - 0.5
    x = (np.arange(out_width, dtype=np.float32) + 0.5) * src_width / out_width - 0.5
    y = np.clip(y, 0.0, src_height - 1.0)
    x = np.clip(x, 0.0, src_width - 1.0)

    y0 = np.floor(y).astype(np.int32)
    x0 = np.floor(x).astype(np.int32)
    y1 = np.minimum(y0 + 1, src_height - 1)
    x1 = np.minimum(x0 + 1, src_width - 1)
    wy = y - y0
    wx = x - x0

    top_left = src[y0[:, None], x0[None, :]]
    top_right = src[y0[:, None], x1[None, :]]
    bottom_left = src[y1[:, None], x0[None, :]]
    bottom_right = src[y1[:, None], x1[None, :]]

    top = top_left * (1.0 - wx)[None, :] + top_right * wx[None, :]
    bottom = bottom_left * (1.0 - wx)[None, :] + bottom_right * wx[None, :]
    return (top * (1.0 - wy)[:, None] + bottom * wy[:, None]).astype(np.float32)


def _sample_bilinear(image: np.ndarray, y: np.ndarray, x: np.ndarray) -> np.ndarray:
    src = _normalizar_tinta(image)
    height, width = src.shape
    valid = (x >= 0.0) & (x <= width - 1.0) & (y >= 0.0) & (y <= height - 1.0)

    x_clip = np.clip(x, 0.0, width - 1.0)
    y_clip = np.clip(y, 0.0, height - 1.0)
    x0 = np.floor(x_clip).astype(np.int32)
    y0 = np.floor(y_clip).astype(np.int32)
    x1 = np.minimum(x0 + 1, width - 1)
    y1 = np.minimum(y0 + 1, height - 1)
    wx = x_clip - x0
    wy = y_clip - y0

    top_left = src[y0, x0]
    top_right = src[y0, x1]
    bottom_left = src[y1, x0]
    bottom_right = src[y1, x1]
    top = top_left * (1.0 - wx) + top_right * wx
    bottom = bottom_left * (1.0 - wx) + bottom_right * wx
    sampled = top * (1.0 - wy) + bottom * wy
    return np.where(valid, sampled, 0.0).astype(np.float32)


def _shift_image(image: np.ndarray, shift_y: int, shift_x: int) -> np.ndarray:
    height, width = image.shape
    shifted = np.zeros_like(image, dtype=np.float32)

    dst_y0 = max(0, shift_y)
    dst_x0 = max(0, shift_x)
    src_y0 = max(0, -shift_y)
    src_x0 = max(0, -shift_x)
    rows = min(height - dst_y0, height - src_y0)
    cols = min(width - dst_x0, width - src_x0)

    if rows > 0 and cols > 0:
        shifted[dst_y0:dst_y0 + rows, dst_x0:dst_x0 + cols] = image[
            src_y0:src_y0 + rows,
            src_x0:src_x0 + cols,
        ]

    return shifted


def center_by_mass(image: np.ndarray) -> np.ndarray:
    """Centraliza uma imagem 28x28 pelo centro de massa da tinta."""
    ink = _normalizar_tinta(image)
    if ink.shape != (IMG_HEIGHT_C, IMG_WIDTH_C):
        raise ValueError(f"center_by_mass espera imagem 28x28; recebido {ink.shape}")

    total_ink = float(np.sum(ink))
    if total_ink <= 0.0:
        raise ValueError("imagem sem tinta para centralizar")

    rows, cols = np.indices(ink.shape, dtype=np.float32)
    center_x = float(np.sum(cols * ink) / total_ink)
    center_y = float(np.sum(rows * ink) / total_ink)
    target_x = IMG_WIDTH_C / 2.0
    target_y = IMG_HEIGHT_C / 2.0
    shift_x = round(target_x - center_x)
    shift_y = round(target_y - center_y)
    return _shift_image(ink, int(shift_y), int(shift_x))


def preprocess_for_fpga(image: np.ndarray, threshold: float) -> np.ndarray:
    """
    Replica em NumPy o funil final do canvas: crop, resize para miolo 20,
    centralizacao por centro de massa, binarizacao e flatten 784.
    """
    if not (0.0 <= threshold <= 1.0):
        raise ValueError("threshold deve estar entre 0.0 e 1.0")

    source = _normalizar_tinta(image)
    ink_mask = source >= INK_DETECT_THRESHOLD_C
    if not np.any(ink_mask):
        raise ValueError("imagem sem tinta apos augmentation")

    ys, xs = np.where(ink_mask)
    min_y, max_y = int(ys.min()), int(ys.max())
    min_x, max_x = int(xs.min()), int(xs.max())
    crop = source[min_y:max_y + 1, min_x:max_x + 1]
    digit_height, digit_width = crop.shape

    if MNIST_INNER_SIZE_C <= 0 or MNIST_INNER_SIZE_C > min(IMG_WIDTH_C, IMG_HEIGHT_C):
        raise ValueError("MNIST_INNER_SIZE_C invalido para grade 28x28")

    scale = min(MNIST_INNER_SIZE_C / digit_width, MNIST_INNER_SIZE_C / digit_height)
    scaled_width = max(1, round(digit_width * scale))
    scaled_height = max(1, round(digit_height * scale))
    scaled = _resize_bilinear(crop, scaled_height, scaled_width)

    normalized = np.zeros((IMG_HEIGHT_C, IMG_WIDTH_C), dtype=np.float32)
    offset_x = (IMG_WIDTH_C - scaled_width) // 2
    offset_y = (IMG_HEIGHT_C - scaled_height) // 2
    normalized[
        offset_y:offset_y + scaled_height,
        offset_x:offset_x + scaled_width,
    ] = scaled

    frame = center_by_mass(normalized)
    binary = (frame >= threshold).astype(np.float32)
    if not np.any(binary):
        raise ValueError("pre-processamento gerou frame vazio")
    return binary.reshape((IMG_BITS_C,))


def _max_filter_3x3(image: np.ndarray) -> np.ndarray:
    padded = np.pad(_normalizar_tinta(image), 1, mode="constant", constant_values=0.0)
    out = np.zeros_like(image, dtype=np.float32)
    for dy in range(3):
        for dx in range(3):
            out = np.maximum(out, padded[dy:dy + image.shape[0], dx:dx + image.shape[1]])
    return out


def _min_filter_3x3(image: np.ndarray) -> np.ndarray:
    padded = np.pad(_normalizar_tinta(image), 1, mode="constant", constant_values=0.0)
    out = np.ones_like(image, dtype=np.float32)
    for dy in range(3):
        for dx in range(3):
            out = np.minimum(out, padded[dy:dy + image.shape[0], dx:dx + image.shape[1]])
    return out


def _rotate_scale_on_canvas(image: np.ndarray, angle_deg: float, scale: float) -> np.ndarray:
    source = np.zeros((AUG_CANVAS_SIZE_C, AUG_CANVAS_SIZE_C), dtype=np.float32)
    ink = _normalizar_tinta(image)
    offset_y = (AUG_CANVAS_SIZE_C - ink.shape[0]) // 2
    offset_x = (AUG_CANVAS_SIZE_C - ink.shape[1]) // 2
    source[offset_y:offset_y + ink.shape[0], offset_x:offset_x + ink.shape[1]] = ink

    rows, cols = np.indices(source.shape, dtype=np.float32)
    center = (AUG_CANVAS_SIZE_C - 1) / 2.0
    x_centered = cols - center
    y_centered = rows - center
    angle_rad = math.radians(angle_deg)
    cos_a = math.cos(angle_rad)
    sin_a = math.sin(angle_rad)
    safe_scale = max(0.01, float(scale))

    src_x = (cos_a * x_centered + sin_a * y_centered) / safe_scale + center
    src_y = (-sin_a * x_centered + cos_a * y_centered) / safe_scale + center
    return _sample_bilinear(source, src_y, src_x)


def _clamp_threshold(value: float) -> float:
    return max(0.0, min(1.0, float(value)))


def augment_image(
    image: np.ndarray,
    rng: np.random.Generator,
    profile: str,
    threshold: float,
) -> np.ndarray:
    """Aplica augmentation antes do preprocess final compativel com o canvas."""
    config = AUG_PROFILE_CONFIGS_C[profile]
    rotation_deg = float(config["rotation_deg"])
    angle = float(rng.uniform(-rotation_deg, rotation_deg))
    scale = float(rng.uniform(config["scale_min"], config["scale_max"]))
    augmented = _rotate_scale_on_canvas(image, angle, scale)

    if float(rng.random()) < float(config["thickness_prob"]):
        if float(rng.random()) < float(config["erode_prob"]):
            filtered = _min_filter_3x3(augmented)
        else:
            filtered = _max_filter_3x3(augmented)
        augmented = np.clip(0.65 * filtered + 0.35 * augmented, 0.0, 1.0)

    intensity_delta = float(config["intensity_jitter"])
    intensity_scale = float(rng.uniform(1.0 - intensity_delta, 1.0 + intensity_delta))
    augmented = np.clip(augmented * intensity_scale, 0.0, 1.0)

    threshold_delta = float(config["threshold_jitter"])
    aug_threshold = _clamp_threshold(float(threshold) + float(rng.uniform(-threshold_delta, threshold_delta)))

    try:
        return preprocess_for_fpga(augmented, aug_threshold)
    except ValueError:
        return binarizar_mnist(image.reshape((1, IMG_HEIGHT_C, IMG_WIDTH_C)), threshold)[0]


def augment_dataset(
    x_raw: np.ndarray,
    y: np.ndarray,
    factor: int,
    profile: str,
    seed: int,
    threshold: float,
    include_original: bool,
) -> tuple[np.ndarray, np.ndarray]:
    if profile not in AUG_PROFILE_CONFIGS_C:
        raise ValueError(f"perfil de augmentation desconhecido: {profile}")
    if factor < 0:
        raise ValueError("--aug-factor deve ser >= 0")

    y_base = y.astype(np.int64)
    arrays: list[np.ndarray] = []
    labels: list[np.ndarray] = []

    if include_original:
        arrays.append(binarizar_mnist(x_raw, threshold))
        labels.append(y_base)

    if factor > 0:
        rng = np.random.default_rng(seed)
        total = int(x_raw.shape[0]) * int(factor)
        x_aug = np.empty((total, IMG_BITS_C), dtype=np.float32)
        y_aug = np.empty((total,), dtype=np.int64)
        out_index = 0

        for image_index, image in enumerate(x_raw):
            if image_index > 0 and image_index % 10000 == 0:
                print(f"  augmentation: {image_index}/{x_raw.shape[0]} imagens base processadas")
            for _ in range(factor):
                x_aug[out_index, :] = augment_image(image, rng, profile, threshold)
                y_aug[out_index] = y_base[image_index]
                out_index += 1

        arrays.append(x_aug)
        labels.append(y_aug)

    if not arrays:
        return np.empty((0, IMG_BITS_C), dtype=np.float32), np.empty((0,), dtype=np.int64)

    return np.concatenate(arrays, axis=0), np.concatenate(labels, axis=0)


# -----------------------------------------------------------------------------
# Modelo TF/Keras
# -----------------------------------------------------------------------------

def criar_modelo_linear(tf):
    modelo = tf.keras.Sequential(
        [
            tf.keras.Input(shape=(IMG_BITS_C,), name="mnist_binario_784"),
            tf.keras.layers.Dense(NUM_DIGITOS_C, activation=None, name="logits"),
        ]
    )
    modelo.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=1e-3),
        loss=tf.keras.losses.SparseCategoricalCrossentropy(from_logits=True),
        metrics=["accuracy"],
    )
    return modelo


def carregar_ou_treinar_modelo(tf, args, x_train, y_train, x_test, y_test):
    if args.modelo is not None:
        caminho_modelo = Path(args.modelo)
        if not caminho_modelo.exists():
            raise SystemExit(f"Erro: modelo não encontrado: {caminho_modelo}")
        modelo = tf.keras.models.load_model(caminho_modelo)
        return modelo

    modelo = criar_modelo_linear(tf)
    callbacks = []

    if args.early_stop:
        callbacks.append(
            tf.keras.callbacks.EarlyStopping(
                monitor="val_accuracy",
                patience=3,
                restore_best_weights=True,
            )
        )

    modelo.fit(
        x_train,
        y_train,
        epochs=args.epochs,
        batch_size=args.batch_size,
        validation_split=args.validation_split,
        shuffle=True,
        verbose=2,
        callbacks=callbacks,
    )

    perda, acc = modelo.evaluate(x_test, y_test, verbose=0)
    print(f"Acurácia float no teste MNIST binarizado: {acc:.4f} (loss={perda:.4f})")

    return modelo


def extrair_pesos_dense_784x10(modelo) -> Tuple[np.ndarray, np.ndarray, str]:
    """Retorna W(784,10), b(10) da camada compatível com o hardware."""
    for camada in modelo.layers:
        pesos = camada.get_weights()
        if len(pesos) != 2:
            continue

        w, b = pesos
        if tuple(w.shape) == (IMG_BITS_C, NUM_DIGITOS_C) and tuple(b.shape) == (NUM_DIGITOS_C,):
            return w.astype(np.float64), b.astype(np.float64), camada.name

    descricoes = []
    for camada in modelo.layers:
        pesos = camada.get_weights()
        if pesos:
            descricoes.append(f"{camada.name}: {[tuple(p.shape) for p in pesos]}")

    raise SystemExit(
        "Erro: não encontrei no modelo uma camada Dense compatível com o hardware "
        f"(pesos {IMG_BITS_C}x{NUM_DIGITOS_C}, bias {NUM_DIGITOS_C}).\n"
        "Camadas com pesos encontradas:\n  - " + "\n  - ".join(descricoes)
    )


# -----------------------------------------------------------------------------
# Quantização do classificador denso
# -----------------------------------------------------------------------------

def quantizar_int8_com_bias(
    w_float: np.ndarray,
    b_float: np.ndarray,
    escala_manual: float | None,
):
    """
    Quantização simétrica por escala única.

    Como o hardware soma apenas pesos int8 quando pixel=1, usar a mesma escala
    para W e b preserva aproximadamente o argmax dos logits float:

        argmax(x@W + b) ~= argmax(x@round(W*s) + round(b*s))
    """
    if escala_manual is None:
        max_abs = float(np.max(np.abs(w_float)))
        if max_abs == 0.0:
            escala = 1.0
        else:
            escala = 127.0 / max_abs
    else:
        if escala_manual <= 0.0:
            raise ValueError("--escala deve ser positiva")
        escala = float(escala_manual)

    q_w = np.rint(w_float * escala)
    q_w = np.clip(q_w, -127, 127).astype(np.int16)

    q_b = np.rint(b_float * escala).astype(np.int64)

    min_bias = -(2 ** (SCORE_DENSO_WIDTH_C - 1))
    max_bias = (2 ** (SCORE_DENSO_WIDTH_C - 1)) - 1

    if np.any(q_b < min_bias) or np.any(q_b > max_bias):
        raise SystemExit(
            "Erro: algum bias quantizado não cabe em score_denso_t "
            f"signed({SCORE_DENSO_WIDTH_C - 1} downto 0).\n"
            f"Faixa permitida: {min_bias}..{max_bias}.\n"
            f"Biases obtidos: {q_b.tolist()}\n"
            "Tente reduzir --escala ou retreinar o modelo."
        )

    return q_w, q_b, escala


def avaliar_quantizado(
    x_bin: np.ndarray,
    y: np.ndarray,
    q_w: np.ndarray,
    q_b: np.ndarray,
    nome: str,
) -> float:
    logits = x_bin.astype(np.int64) @ q_w.astype(np.int64) + q_b.astype(np.int64)
    pred = np.argmax(logits, axis=1)
    acc = float(np.mean(pred == y))
    print(f"Acurácia quantizada ({nome}): {acc:.4f}")
    return acc


def evaluate_dense(
    x_bin: np.ndarray,
    y: np.ndarray,
    q_w: np.ndarray,
    q_b: np.ndarray,
    nome: str,
) -> float:
    return avaliar_quantizado(x_bin, y, q_w, q_b, nome)


# -----------------------------------------------------------------------------
# Máscaras top-64 do classificador binário
# -----------------------------------------------------------------------------

def escolher_indices_top64_por_heatmap(
    x_bin: np.ndarray,
    y: np.ndarray,
    top_k: int,
    penalidade: float = TOP64_PENALIDADE_C,
    usar_max_competidor: bool = TOP64_USAR_MAX_COMPETIDOR_C,
) -> np.ndarray:
    """
    Escolhe pixels top-K para o classificador binário combinacional usando um
    critério DISCRIMINATIVO (one-vs-rest).
 
    Critério:
 
      freq_d(p)   = média de ativação do pixel p nas imagens cujo label e d
      comp_d(p)   = frequência do pixel p nos OUTROS dígitos
                    (média dos 9 outros heatmaps por padrão, ou o máximo deles)
      score_d(p)  = freq_d(p) - penalidade * comp_d(p)

    penalidade >= 0 controla quanto pixels comuns a outros dígitos são
    penalizados. usar_max_competidor troca a média dos outros dígitos pelo pior
    competidor por pixel.
    """
    if top_k <= 0 or top_k > IMG_BITS_C:
        raise ValueError(f"top_k deve estar em 1..{IMG_BITS_C}")
 
    if x_bin.ndim != 2 or x_bin.shape[1] != IMG_BITS_C:
        raise ValueError(f"x_bin deve ter formato (N, {IMG_BITS_C}); recebido {x_bin.shape}")
 
    if y.ndim != 1 or y.shape[0] != x_bin.shape[0]:
        raise ValueError("y deve ser vetor 1D com o mesmo número de amostras de x_bin")
 
    # 1) Heatmap (frequência média de ativação por pixel) para cada dígito.
    freq = np.zeros((NUM_DIGITOS_C, IMG_BITS_C), dtype=np.float64)
    for d in range(NUM_DIGITOS_C):
        mascara_d = y == d
        qtd = int(np.sum(mascara_d))
        if qtd == 0:
            raise ValueError(f"não há imagens do dígito {d} para gerar a máscara top-{top_k}")
        freq[d, :] = np.mean(x_bin[mascara_d, :], axis=0)
 
    # 2) Score discriminativo por dígito e seleção dos top-K.
    indices = np.zeros((NUM_DIGITOS_C, top_k), dtype=np.int64)
    todos = np.arange(IMG_BITS_C)
 
    for d in range(NUM_DIGITOS_C):
        outros = np.delete(freq, d, axis=0)  # (9, 784): os 9 outros heatmaps
        if usar_max_competidor:
            competidor = outros.max(axis=0)
        else:
            competidor = outros.mean(axis=0)
 
        score = freq[d, :] - float(penalidade) * competidor
 
        # Mesma regra de desempate do original: maior score primeiro,
        # menor índice primeiro em caso de empate (determinístico).
        ordem = np.lexsort((todos, -score))
        indices[d, :] = ordem[:top_k]
 
    return indices


def avaliar_top64_binario(
    x_bin: np.ndarray,
    y: np.ndarray,
    indices_top64: np.ndarray,
    nome: str,
) -> float:
    """
    Avalia em Python a mesma regra lógica do classificador binário VHDL:

      score_d = soma dos pixels ativos nos índices da máscara d
      pred    = argmax_d score_d

    Esta avaliação é apenas diagnóstica; não altera o classificador denso.
    """
    if indices_top64.ndim != 2 or indices_top64.shape[0] != NUM_DIGITOS_C:
        raise ValueError("indices_top64 deve ter formato (10, top_k)")

    scores = np.zeros((x_bin.shape[0], NUM_DIGITOS_C), dtype=np.int32)

    for d in range(NUM_DIGITOS_C):
        scores[:, d] = np.sum(x_bin[:, indices_top64[d, :]], axis=1).astype(np.int32)

    pred = np.argmax(scores, axis=1)
    acc = float(np.mean(pred == y))

    print(f"Acurácia top-{indices_top64.shape[1]} binária ({nome}): {acc:.4f}")
    return acc


def evaluate_binary(
    x_bin: np.ndarray,
    y: np.ndarray,
    indices_top64: np.ndarray,
    nome: str,
) -> float:
    return avaliar_top64_binario(x_bin, y, indices_top64, nome)


# -----------------------------------------------------------------------------
# Escrita dos artefatos VHDL
# -----------------------------------------------------------------------------

def cabecalho_gerado(
    nome_arquivo: str,
    descricao: str,
    parametros: list[tuple[str, str]] | None = None,
) -> str:
    sep = "-------------------------------------------------------------------------------\n"
    linhas = [
        sep,
        f"-- Arquivo   : {nome_arquivo}\n",
        f"-- Descricao : {descricao}\n",
    ]

    if parametros:
        linhas.append("-- Parametros de geracao:\n")
        for nome, valor in parametros:
            linhas.append(f"--   {nome}: {valor}\n")

    linhas.extend(
        [
            sep,
            "-- ATENCAO: arquivo gerado automaticamente por gerar_pesos.py.\n",
            sep,
            "\n",
        ]
    )
    return "".join(linhas)


def escrever_mascaras_top64_pkg(
    caminho: Path,
    indices: np.ndarray,
    top_k: int,
    threshold: float,
    penalidade: float,
    usar_max_competidor: bool,
) -> None:
    linhas: list[str] = []
    competidor = "maximo" if usar_max_competidor else "media"

    linhas.append(
        cabecalho_gerado(
            "mascaras_top64_pkg.vhd",
            "Pacote de mascaras top-k do classificador binario.",
            [
                ("threshold", f"{threshold:.12g}"),
                ("top_k", str(top_k)),
                ("penalidade", f"{penalidade:.12g}"),
                ("competidor", competidor),
            ],
        )
    )
    linhas.append("library ieee;\n")
    linhas.append("use ieee.std_logic_1164.all;\n")
    linhas.append("use ieee.numeric_std.all;\n")
    linhas.append("use work.mnist_tipos_pkg.all;\n\n")
    linhas.append("package mascaras_top64_pkg is\n\n")
    linhas.append("    --------------------------------------------------------------------\n")
    linhas.append(f"    -- Indices top-{top_k} gerados por heatmap discriminativo.\n")
    linhas.append("    -- Para cada digito d, o score de cada pixel e calculado como:\n")
    linhas.append("    -- score_d(p) = freq_d(p) - penalidade * competidor_d(p).\n")
    linhas.append(f"    -- Threshold de binarizacao usado no MNIST: {threshold:.12g}\n")
    linhas.append(f"    -- Penalidade do competidor: {penalidade:.12g}\n")
    linhas.append(f"    -- Competidor usado: {competidor}\n")
    linhas.append("    --------------------------------------------------------------------\n")
    linhas.append("    constant INDICES_TOP64_C : indices_top64_array_t := (\n")

    for d in range(NUM_DIGITOS_C):
        linhas.append(f"        {d} => (\n")

        for k in range(top_k):
            sep = "," if k < top_k - 1 else ""
            linhas.append(f"            {k:2d} => {int(indices[d, k]):3d}{sep}\n")

        sep_d = "," if d < NUM_DIGITOS_C - 1 else ""
        linhas.append(f"        ){sep_d}\n")

    linhas.append("    );\n\n")
    linhas.append("end package mascaras_top64_pkg;\n")

    caminho.write_text("".join(linhas), encoding="utf-8")


def escrever_bias_densos_pkg(caminho: Path, q_b: np.ndarray, escala: float) -> None:
    linhas: list[str] = []

    linhas.append(
        cabecalho_gerado(
            "bias_densos_pkg.vhd",
            "Pacote de biases quantizados do classificador denso.",
            [("escala_quantizacao", f"{escala:.12g}")],
        )
    )
    linhas.append("library ieee;\n")
    linhas.append("use ieee.std_logic_1164.all;\n")
    linhas.append("use ieee.numeric_std.all;\n")
    linhas.append("use work.mnist_tipos_pkg.all;\n\n")
    linhas.append("package bias_densos_pkg is\n\n")
    linhas.append("    --------------------------------------------------------------------\n")
    linhas.append("    -- Biases quantizados com a mesma escala dos pesos int8.\n")
    linhas.append(f"    -- Escala de quantizacao: {escala:.12g}\n")
    linhas.append("    --------------------------------------------------------------------\n")
    linhas.append("    constant BIAS_DENSOS_C : score_denso_array_t := (\n")

    for d in range(NUM_DIGITOS_C):
        sep = "," if d < NUM_DIGITOS_C - 1 else ""
        linhas.append(f"        {d} => to_signed({int(q_b[d])}, SCORE_DENSO_WIDTH_C){sep}\n")

    linhas.append("    );\n\n")
    linhas.append("end package bias_densos_pkg;\n")

    caminho.write_text("".join(linhas), encoding="utf-8")


def int8_para_u8(valor: int) -> int:
    """Converte inteiro assinado de 8 bits para representação unsigned 0..255."""
    return int(valor) & 0xFF


def empacotar_pesos_pixel_hex(q_w_linha: np.ndarray) -> str:
    """
    Empacota 10 pesos int8 em uma palavra de 80 bits.

    O VHDL desempacota assim:

      pesos_pixel(d) <= signed(palavra((d+1)*8-1 downto d*8));

    Logo, d0 fica no byte menos significativo e d9 no byte mais significativo.
    """
    palavra = 0

    for d in range(NUM_DIGITOS_C):
        palavra |= int8_para_u8(int(q_w_linha[d])) << (PESO_WIDTH_C * d)

    return f"{palavra:0{ROM_DATA_WIDTH_C // 4}X}"


def escrever_rom_pesos_densos_vhd(caminho: Path, q_w: np.ndarray) -> None:
    """Sobrescreve rom_pesos_densos.vhd com os pesos densos embutidos."""
    linhas: list[str] = []

    linhas.append(
        cabecalho_gerado(
            "rom_pesos_densos.vhd",
            "ROM sincrona de pesos densos com 784 enderecos uteis x 80 bits.",
            [
                ("rom_depth", "1024"),
                ("enderecos_validos", "0..783"),
                ("enderecos_zerados", "784..1023"),
                ("pesos_por_pixel", str(NUM_DIGITOS_C)),
                ("ordem_palavra", "[d9 | d8 | ... | d1 | d0], d0 no byte LSB"),
                ("latencia", "1 ciclo apos endereco_pixel"),
                ("romstyle", "M10K"),
            ],
        )
    )

    linhas.append("library ieee;\n")
    linhas.append("use ieee.std_logic_1164.all;\n")
    linhas.append("use ieee.numeric_std.all;\n")
    linhas.append("use work.mnist_tipos_pkg.all;\n\n")

    linhas.append("entity rom_pesos_densos is\n")
    linhas.append("    port (\n")
    linhas.append("        ----------------------------------------------------------------\n")
    linhas.append("        -- Clock para leitura sincrona da ROM\n")
    linhas.append("        ----------------------------------------------------------------\n")
    linhas.append("        clock          : in  std_logic;\n\n")
    linhas.append("        ----------------------------------------------------------------\n")
    linhas.append("        -- Endereco do pixel atual: 0 a 783 durante a classificacao\n")
    linhas.append("        ----------------------------------------------------------------\n")
    linhas.append("        endereco_pixel : in  unsigned(9 downto 0);\n\n")
    linhas.append("        ----------------------------------------------------------------\n")
    linhas.append("        -- Dez pesos associados ao pixel atual, um por digito\n")
    linhas.append("        -- validos 1 ciclo apos o endereco ser apresentado\n")
    linhas.append("        ----------------------------------------------------------------\n")
    linhas.append("        pesos_pixel    : out peso10_array_t\n")
    linhas.append("    );\n")
    linhas.append("end entity rom_pesos_densos;\n\n\n")

    linhas.append("architecture arch of rom_pesos_densos is\n\n")
    linhas.append("    constant DATA_WIDTH_C : natural := NUM_DIGITOS_C * PESO_WIDTH_C;\n")
    linhas.append("    constant NUM_PIXELS_C : natural := IMG_BITS_C; -- 784\n")
    linhas.append("    constant ROM_DEPTH_C  : natural := 1024;\n\n")
    linhas.append("    type rom_t is array (0 to ROM_DEPTH_C-1) of std_logic_vector(DATA_WIDTH_C-1 downto 0);\n\n")
    linhas.append("    signal ROM_PESOS_S : rom_t := (\n")

    for pix in range(IMG_BITS_C):
        palavra_hex = empacotar_pesos_pixel_hex(q_w[pix, :])
        linhas.append(f"        {pix:3d} => x\"{palavra_hex}\",\n")

    linhas.append("        others => (others => '0')\n")
    linhas.append("    );\n\n")

    linhas.append("    attribute romstyle : string;\n")
    linhas.append("    attribute romstyle of ROM_PESOS_S : signal is \"M10K\";\n\n")

    linhas.append("    signal palavra : std_logic_vector(DATA_WIDTH_C-1 downto 0) := (others => '0');\n\n")

    linhas.append("begin\n\n")
    linhas.append("    -- Leitura sincrona.\n")
    linhas.append("    -- ROM_PESOS_S tem ROM_DEPTH_C = 1024 posicoes.\n")
    linhas.append("    -- Enderecos 0..783 contem pesos reais.\n")
    linhas.append("    -- Enderecos 784..1023 sao zerados.\n")
    linhas.append("    process(clock)\n")
    linhas.append("    begin\n")
    linhas.append("        if rising_edge(clock) then\n")
    linhas.append("            palavra <= ROM_PESOS_S(to_integer(endereco_pixel));\n")
    linhas.append("        end if;\n")
    linhas.append("    end process;\n\n")

    linhas.append("    -- Desempacota os 10 pesos para o array tipado.\n")
    linhas.append("    -- Ordenacao: pesos_pixel(0) ocupa os bits menos significativos.\n")
    linhas.append("    gen_unpack: for d in 0 to NUM_DIGITOS_C-1 generate\n")
    linhas.append("        pesos_pixel(d) <= signed(palavra((d+1)*PESO_WIDTH_C-1 downto d*PESO_WIDTH_C));\n")
    linhas.append("    end generate;\n\n")

    linhas.append("end architecture arch;\n")

    caminho.write_text("".join(linhas), encoding="utf-8")


def escrever_info(
    caminho: Path,
    camada: str,
    escala: float,
    q_w: np.ndarray,
    q_b: np.ndarray,
    acc_train: float,
    acc_test: float,
    acc_top64_train: float,
    acc_top64_test: float,
    threshold: float,
    top_k: int,
    penalidade: float,
    usar_max_competidor: bool,
    augmented: bool,
    aug_factor: int,
    aug_profile: str,
    aug_seed: int,
    train_samples_original: int,
    train_samples_final: int,
    acc_aug_test: float | None,
    acc_top64_aug_test: float | None,
    aug_test_samples: int | None,
    modelo_carregado: bool,
) -> None:
    augmented_text = "sim" if augmented else "nao"
    modelo_carregado_text = "sim" if modelo_carregado else "nao"
    competidor_texto = (
        "maximo dos outros digitos" if usar_max_competidor else "media dos outros digitos"
    )
    dense_aug_line = (
        "  Acuracia quantizada teste augmentado/canvas-like: "
        f"{acc_aug_test:.6f}\n"
        if acc_aug_test is not None
        else "  Acuracia quantizada teste augmentado/canvas-like: n/a\n"
    )
    binary_aug_line = (
        f"  Acuracia top-{top_k} teste augmentado/canvas-like: "
        f"{acc_top64_aug_test:.6f}\n"
        if acc_top64_aug_test is not None
        else f"  Acuracia top-{top_k} teste augmentado/canvas-like: n/a\n"
    )
    aug_test_samples_text = (
        str(aug_test_samples) if aug_test_samples is not None else "n/a"
    )
    modelo_obs = (
        "  Observacao --modelo: o classificador denso carregado nao foi retreinado; "
        "a augmentation afeta as mascaras top-k e as avaliacoes.\n"
        if augmented and modelo_carregado
        else ""
    )

    texto = f"""Arquivo gerado automaticamente por gerar_pesos.py

Camada Keras usada no classificador denso: {camada}
Threshold de binarizacao MNIST: {threshold:.12g}

Augmentation de treino:
  Ativa: {augmented_text}
  aug_factor: {aug_factor}
  aug_profile: {aug_profile}
  aug_seed: {aug_seed}
  Amostras MNIST treino originais: {train_samples_original}
  Amostras finais de treino: {train_samples_final}
  Amostras teste augmentado/canvas-like: {aug_test_samples_text}
  Modelo denso carregado por --modelo: {modelo_carregado_text}
{modelo_obs}

Classificador denso quantizado:
  Escala de quantizacao: {escala:.12g}
  Faixa q_w: {int(q_w.min())}..{int(q_w.max())}
  Biases q_b: {q_b.astype(int).tolist()}
  Acuracia quantizada treino final: {acc_train:.6f}
  Acuracia quantizada teste MNIST original: {acc_test:.6f}
{dense_aug_line.rstrip()}

Classificador binario top-{top_k}:
  Mascaras geradas por heatmap discriminativo one-vs-rest.
  score_d(p): freq_d(p) - penalidade * competidor_d(p)
  penalidade: {penalidade:.12g}
  competidor: {competidor_texto}
  Acuracia top-{top_k} treino final: {acc_top64_train:.6f}
  Acuracia top-{top_k} teste MNIST original: {acc_top64_test:.6f}
{binary_aug_line.rstrip()}

Convencao da ROM de pesos densos:
  endereco = indice do pixel row-major, i = linha*28 + coluna
  palavra  = [d9 | d8 | ... | d1 | d0]
  d0 ocupa os 8 bits menos significativos
  cada peso e interpretado no VHDL como signed(7 downto 0)

Observacao:
  O modo --augmented busca melhorar robustez a entrada dinamica/canvas-like
  com variacoes de escala, espessura e estilo. O objetivo nao e apenas maximizar
  a acuracia no MNIST limpo original.
"""

    caminho.write_text(texto, encoding="utf-8")


def validar_dimensoes(q_w: np.ndarray, q_b: np.ndarray) -> None:
    if q_w.shape != (IMG_BITS_C, NUM_DIGITOS_C):
        raise ValueError(f"q_w tem formato {q_w.shape}, esperado {(IMG_BITS_C, NUM_DIGITOS_C)}")

    if q_b.shape != (NUM_DIGITOS_C,):
        raise ValueError(f"q_b tem formato {q_b.shape}, esperado {(NUM_DIGITOS_C,)}")


def resolver_caminhos_artefatos_modelo(
    salvar_modelo: str | None,
) -> tuple[Path, Path] | None:
    if salvar_modelo is None:
        return None

    destino = Path(salvar_modelo).expanduser()
    if destino.exists() and destino.is_dir():
        return (
            destino / DENSE_MODEL_FILENAME_C,
            destino / BINARY_MODEL_FILENAME_C,
        )

    if destino.suffix.lower() == ".keras":
        return destino, destino.parent / BINARY_MODEL_FILENAME_C

    return (
        destino / DENSE_MODEL_FILENAME_C,
        destino / BINARY_MODEL_FILENAME_C,
    )


def salvar_artefatos_modelo(
    modelo,
    indices_top64: np.ndarray,
    salvar_modelo: str | None,
) -> list[Path]:
    caminhos = resolver_caminhos_artefatos_modelo(salvar_modelo)
    if caminhos is None:
        return []

    caminho_denso, caminho_binario = caminhos
    caminho_denso.parent.mkdir(parents=True, exist_ok=True)
    caminho_binario.parent.mkdir(parents=True, exist_ok=True)

    modelo.save(str(caminho_denso))
    np.save(caminho_binario, indices_top64.astype(np.int16))
    return [caminho_denso, caminho_binario]


# -----------------------------------------------------------------------------
# CLI
# -----------------------------------------------------------------------------

def parse_args(argv: list[str]) -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent

    parser = argparse.ArgumentParser(
        description=(
            "Gera mascaras_top64_pkg.vhd, bias_densos_pkg.vhd e "
            "sobrescreve rom_pesos_densos.vhd para o classificador MNIST. "
            "Com --salvar-modelo, tambem gera classificador_denso.keras e "
            "classificador_binario.npy para o trace_benchmark.py."
        )
    )

    parser.add_argument(
        "--saida-dir",
        default=str(script_dir),
        help=(
            "Diretorio onde os arquivos gerados serao escritos. "
            "Padrao: mesmo diretorio deste script."
        ),
    )
    parser.add_argument(
        "--modelo",
        default=None,
        help="Modelo .keras/.h5 ja treinado. Deve conter Dense com pesos (784,10).",
    )
    parser.add_argument(
        "--salvar-modelo",
        nargs="?",
        const=str(script_dir),
        default=None,
        help=(
            "Opcional. Salva classificador_denso.keras e classificador_binario.npy. "
            "Sem valor, usa o diretorio deste script; com diretorio, usa esse "
            "diretorio; com arquivo .keras, salva o denso nesse arquivo e o "
            "binario no mesmo diretorio."
        ),
    )
    parser.add_argument(
        "--epochs",
        type=int,
        default=25,
        help="Epocas de treinamento quando --modelo nao for usado. Padrao: 25.",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=128,
        help="Batch size do treinamento. Padrao: 128.",
    )
    parser.add_argument(
        "--validation-split",
        type=float,
        default=0.10,
        help="Fracao de validacao no treino. Padrao: 0.10.",
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=0.50,
        help="Limiar de binarizacao dos pixels MNIST normalizados. Padrao: 0.50.",
    )
    parser.add_argument(
        "--top-k",
        type=int,
        default=TOP_K_C,
        help="Quantidade de indices por digito. Para o VHDL atual, mantenha 64.",
    )
    parser.add_argument(
        "--penalidade",
        type=float,
        default=TOP64_PENALIDADE_C,
        help=(
            "Peso do termo competidor no score top-k: "
            "freq_d - penalidade*competidor. Padrao: 0.1."
        ),
    )
    parser.add_argument(
        "--usar-max-competidor",
        action="store_true",
        default=TOP64_USAR_MAX_COMPETIDOR_C,
        help=(
            "Usa o maximo dos outros digitos como competidor. "
            "Padrao: usa a media dos outros digitos."
        ),
    )
    parser.add_argument(
        "--escala",
        type=float,
        default=None,
        help="Escala manual de quantizacao. Padrao: 127/max(abs(W)).",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Seed para reprodutibilidade. Padrao: 42.",
    )
    parser.add_argument(
        "--early-stop",
        action="store_true",
        help="Usa EarlyStopping durante o treinamento.",
    )
    parser.add_argument(
        "--augmented",
        action="store_true",
        help="Treina/gera artefatos com augmentations leves antes do preprocess FPGA.",
    )
    parser.add_argument(
        "--aug-factor",
        type=int,
        default=2,
        help=(
            "Quantidade de versoes augmentadas por imagem de treino quando "
            "--augmented estiver ativo. Padrao: 2."
        ),
    )
    parser.add_argument(
        "--aug-seed",
        type=int,
        default=42,
        help="Seed usada exclusivamente para augmentation. Padrao: 42.",
    )
    parser.add_argument(
        "--aug-profile",
        choices=tuple(AUG_PROFILE_CONFIGS_C.keys()),
        default="medio",
        help="Perfil de augmentation: leve, medio ou forte. Padrao: medio.",
    )

    args = parser.parse_args(argv)
    if args.aug_factor < 0:
        parser.error("--aug-factor deve ser >= 0")
    if args.penalidade < 0:
        parser.error("--penalidade deve ser >= 0")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)

    if args.top_k != TOP_K_C:
        print(
            f"Aviso: --top-k={args.top_k}, mas mnist_tipos_pkg.vhd define TOP_K_C={TOP_K_C}. "
            "Altere o VHDL se realmente quiser outro valor.",
            file=sys.stderr,
        )

    saida_dir = Path(args.saida_dir).resolve()
    saida_dir.mkdir(parents=True, exist_ok=True)

    configurar_seed(tf, args.seed)

    print("Carregando MNIST...")
    x_train_raw, y_train_original, x_test_raw, y_test = carregar_mnist_bruto(tf)
    x_test = binarizar_mnist(x_test_raw, args.threshold)

    if args.augmented:
        print(
            "Gerando treino com augmentation "
            f"(factor={args.aug_factor}, profile={args.aug_profile}, seed={args.aug_seed})..."
        )
        x_train, y_train = augment_dataset(
            x_train_raw,
            y_train_original,
            factor=args.aug_factor,
            profile=args.aug_profile,
            seed=args.aug_seed,
            threshold=args.threshold,
            include_original=True,
        )
    else:
        print("Binarizando imagens MNIST de treino no modo original...")
        x_train = binarizar_mnist(x_train_raw, args.threshold)
        y_train = y_train_original

    train_samples_original = int(x_train_raw.shape[0])
    train_samples_final = int(x_train.shape[0])
    print(f"Amostras de treino usadas: {train_samples_final}")

    print("Carregando/treinando modelo linear MNIST...")
    modelo = carregar_ou_treinar_modelo(tf, args, x_train, y_train, x_test, y_test)

    w_float, b_float, nome_camada = extrair_pesos_dense_784x10(modelo)
    print(f"Camada usada para exportacao densa: {nome_camada}")

    q_w, q_b, escala = quantizar_int8_com_bias(w_float, b_float, args.escala)
    validar_dimensoes(q_w, q_b)

    acc_train = evaluate_dense(x_train, y_train, q_w, q_b, "treino final")
    acc_test = evaluate_dense(x_test, y_test, q_w, q_b, "teste MNIST original")

    competidor_top64 = "maximo" if args.usar_max_competidor else "media"
    print(
        f"Gerando mascaras top-{args.top_k} por heatmap discriminativo "
        f"(penalidade={args.penalidade:.12g}, competidor={competidor_top64})..."
    )
    indices = escolher_indices_top64_por_heatmap(
        x_train,
        y_train,
        args.top_k,
        penalidade=args.penalidade,
        usar_max_competidor=args.usar_max_competidor,
    )

    acc_top64_train = evaluate_binary(x_train, y_train, indices, "treino final")
    acc_top64_test = evaluate_binary(x_test, y_test, indices, "teste MNIST original")

    acc_aug_test: float | None = None
    acc_top64_aug_test: float | None = None
    aug_test_samples: int | None = None
    if args.augmented:
        print("Gerando conjunto de teste augmentado/canvas-like para diagnostico...")
        x_test_aug, y_test_aug = augment_dataset(
            x_test_raw,
            y_test,
            factor=1,
            profile=args.aug_profile,
            seed=args.aug_seed + 1,
            threshold=args.threshold,
            include_original=False,
        )
        aug_test_samples = int(x_test_aug.shape[0])
        acc_aug_test = evaluate_dense(
            x_test_aug,
            y_test_aug,
            q_w,
            q_b,
            "teste augmentado/canvas-like",
        )
        acc_top64_aug_test = evaluate_binary(
            x_test_aug,
            y_test_aug,
            indices,
            "teste augmentado/canvas-like",
        )

    caminho_mascaras = saida_dir / "mascaras_top64_pkg.vhd"
    caminho_bias = saida_dir / "bias_densos_pkg.vhd"
    caminho_rom = saida_dir / "rom_pesos_densos.vhd"
    caminho_info = saida_dir / "pesos_quantizados_info.txt"

    escrever_mascaras_top64_pkg(
        caminho_mascaras,
        indices,
        args.top_k,
        args.threshold,
        args.penalidade,
        args.usar_max_competidor,
    )
    escrever_bias_densos_pkg(caminho_bias, q_b, escala)
    escrever_rom_pesos_densos_vhd(caminho_rom, q_w)
    escrever_info(
        caminho_info,
        nome_camada,
        escala,
        q_w,
        q_b,
        acc_train,
        acc_test,
        acc_top64_train,
        acc_top64_test,
        args.threshold,
        args.top_k,
        args.penalidade,
        args.usar_max_competidor,
        args.augmented,
        args.aug_factor,
        args.aug_profile,
        args.aug_seed,
        train_samples_original,
        train_samples_final,
        acc_aug_test,
        acc_top64_aug_test,
        aug_test_samples,
        args.modelo is not None,
    )
    caminhos_modelo = salvar_artefatos_modelo(modelo, indices, args.salvar_modelo)

    print("\nArquivos gerados/atualizados:")
    arquivos_gerados = [caminho_mascaras, caminho_bias, caminho_rom, caminho_info]
    arquivos_gerados.extend(caminhos_modelo)
    for caminho in arquivos_gerados:
        print(f"  - {caminho}")

    print("\nResumo:")
    print(f"  escala = {escala:.12g}")
    print(f"  q_w min/max = {int(q_w.min())}/{int(q_w.max())}")
    print(f"  q_b = {q_b.astype(int).tolist()}")
    print(f"  acc_denso_quant_teste = {acc_test:.4f}")
    print(f"  top{args.top_k}_penalidade = {args.penalidade:.12g}")
    print(f"  top{args.top_k}_competidor = {competidor_top64}")
    print(f"  acc_top{args.top_k}_binario_teste = {acc_top64_test:.4f}")
    if args.augmented:
        print(f"  acc_denso_quant_teste_aug = {acc_aug_test:.4f}")
        print(f"  acc_top{args.top_k}_binario_teste_aug = {acc_top64_aug_test:.4f}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
sota_mnist_gen.py

Treina um modelo CNN forte para MNIST e salva um artefato Keras usado apenas
como referencia software pelo trace_benchmark.py.

Este script nao gera VHDL, nao altera pesos FPGA e nao toca nos artefatos do
classificador embarcado.
"""

from __future__ import annotations

import argparse
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

import numpy as np
import tensorflow as tf

IMG_WIDTH = 28
IMG_HEIGHT = 28
IMG_CHANNELS = 1
NUM_DIGITS = 10
DEFAULT_EPOCHS = 40
DEFAULT_BATCH_SIZE = 128
DEFAULT_SEED = 42
VALIDATION_SPLIT = 0.10
LEARNING_RATE = 1e-3

def configurar_seed(tf: Any, seed: int) -> None:
    np.random.seed(seed)
    try:
        tf.keras.utils.set_random_seed(seed)
    except Exception:
        pass
    try:
        tf.random.set_seed(seed)
    except Exception:
        pass


def validar_argumentos(args: argparse.Namespace) -> None:
    if args.epochs < 1:
        raise SystemExit("Erro: --epochs deve ser pelo menos 1.")
    if args.batch_size < 1:
        raise SystemExit("Erro: --batch-size deve ser pelo menos 1.")


def validar_saidas(saida_modelo: Path, saida_stats: Path, force: bool) -> None:
    existentes = [caminho for caminho in (saida_modelo, saida_stats) if caminho.exists()]
    if existentes and not force:
        lista = "\n".join(f"  - {caminho}" for caminho in existentes)
        raise SystemExit(
            "Erro: arquivo(s) de saida ja existem:\n"
            f"{lista}\n\n"
            "Use --force para sobrescrever."
        )

    saida_modelo.parent.mkdir(parents=True, exist_ok=True)
    saida_stats.parent.mkdir(parents=True, exist_ok=True)


def carregar_mnist(tf: Any) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    (x_train, y_train), (x_test, y_test) = tf.keras.datasets.mnist.load_data()

    x_train = x_train.astype(np.float32) / 255.0
    x_test = x_test.astype(np.float32) / 255.0
    x_train = x_train[..., np.newaxis]
    x_test = x_test[..., np.newaxis]

    return (
        x_train,
        y_train.astype(np.int64),
        x_test,
        y_test.astype(np.int64),
    )


def separar_validacao(
    x_train: np.ndarray,
    y_train: np.ndarray,
    seed: int,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    if not 0.0 < VALIDATION_SPLIT < 1.0:
        raise ValueError("VALIDATION_SPLIT deve estar entre 0 e 1")

    indices = np.arange(x_train.shape[0])
    rng = np.random.default_rng(seed)
    rng.shuffle(indices)

    val_count = max(1, round(x_train.shape[0] * VALIDATION_SPLIT))
    val_indices = indices[:val_count]
    fit_indices = indices[val_count:]

    return (
        x_train[fit_indices],
        y_train[fit_indices],
        x_train[val_indices],
        y_train[val_indices],
    )


def bloco_conv(tf: Any, x: Any, filtros: int, nome: str) -> Any:
    x = tf.keras.layers.Conv2D(
        filtros,
        kernel_size=3,
        padding="same",
        use_bias=False,
        kernel_initializer="he_normal",
        name=f"{nome}_conv",
    )(x)
    x = tf.keras.layers.BatchNormalization(name=f"{nome}_bn")(x)
    return tf.keras.layers.ReLU(name=f"{nome}_relu")(x)


def criar_augmentation(tf: Any, seed: int) -> Any:
    camadas = [
        tf.keras.layers.RandomRotation(
            0.08,
            fill_mode="constant",
            fill_value=0.0,
            seed=seed,
            name="aug_rotation",
        ),
        tf.keras.layers.RandomTranslation(
            0.08,
            0.08,
            fill_mode="constant",
            fill_value=0.0,
            seed=seed + 1,
            name="aug_translation",
        ),
        tf.keras.layers.RandomZoom(
            0.08,
            fill_mode="constant",
            fill_value=0.0,
            seed=seed + 2,
            name="aug_zoom",
        ),
    ]

    if hasattr(tf.keras.layers, "RandomContrast"):
        camadas.append(
            tf.keras.layers.RandomContrast(
                0.10,
                seed=seed + 3,
                name="aug_contrast",
            )
        )

    camadas.append(tf.keras.layers.GaussianNoise(0.03, name="aug_noise"))
    return tf.keras.Sequential(camadas, name="augmentation")


def criar_modelo(tf: Any, usar_augmentation: bool, seed: int) -> Any:
    inputs = tf.keras.Input(
        shape=(IMG_HEIGHT, IMG_WIDTH, IMG_CHANNELS),
        name="mnist_28x28",
    )

    x = inputs
    if usar_augmentation:
        x = criar_augmentation(tf, seed)(x)

    x = bloco_conv(tf, x, 32, "b1_c1")
    x = bloco_conv(tf, x, 32, "b1_c2")
    x = tf.keras.layers.MaxPooling2D(name="b1_pool")(x)
    x = tf.keras.layers.Dropout(0.20, name="b1_dropout")(x)

    x = bloco_conv(tf, x, 64, "b2_c1")
    x = bloco_conv(tf, x, 64, "b2_c2")
    x = tf.keras.layers.MaxPooling2D(name="b2_pool")(x)
    x = tf.keras.layers.Dropout(0.25, name="b2_dropout")(x)

    x = bloco_conv(tf, x, 128, "b3_c1")
    x = bloco_conv(tf, x, 128, "b3_c2")
    x = tf.keras.layers.GlobalAveragePooling2D(name="global_avg_pool")(x)
    x = tf.keras.layers.Dropout(0.35, name="head_dropout_1")(x)

    x = tf.keras.layers.Dense(
        128,
        use_bias=False,
        kernel_initializer="he_normal",
        name="head_dense",
    )(x)
    x = tf.keras.layers.BatchNormalization(name="head_bn")(x)
    x = tf.keras.layers.ReLU(name="head_relu")(x)
    x = tf.keras.layers.Dropout(0.35, name="head_dropout_2")(x)

    outputs = tf.keras.layers.Dense(
        NUM_DIGITS,
        activation="softmax",
        name="probabilidades",
    )(x)

    modelo = tf.keras.Model(inputs=inputs, outputs=outputs, name="sota_mnist_cnn")
    modelo.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=LEARNING_RATE),
        loss=tf.keras.losses.SparseCategoricalCrossentropy(),
        metrics=["accuracy"],
    )
    return modelo


def criar_callbacks(tf: Any, saida_modelo: Path) -> list[Any]:
    return [
        tf.keras.callbacks.ModelCheckpoint(
            filepath=str(saida_modelo),
            monitor="val_accuracy",
            mode="max",
            save_best_only=True,
            verbose=1,
        ),
        tf.keras.callbacks.EarlyStopping(
            monitor="val_accuracy",
            mode="max",
            patience=8,
            restore_best_weights=True,
            verbose=1,
        ),
        tf.keras.callbacks.ReduceLROnPlateau(
            monitor="val_loss",
            factor=0.5,
            patience=3,
            min_lr=1e-5,
            verbose=1,
        ),
    ]


def avaliar_modelo(
    modelo: Any,
    x: np.ndarray,
    y: np.ndarray,
    batch_size: int,
) -> dict[str, float]:
    loss, accuracy = modelo.evaluate(x, y, batch_size=batch_size, verbose=0)
    return {"loss": float(loss), "accuracy": float(accuracy)}


def matriz_confusao(
    modelo: Any,
    x_test: np.ndarray,
    y_test: np.ndarray,
    batch_size: int,
) -> np.ndarray:
    probabilidades = modelo.predict(x_test, batch_size=batch_size, verbose=0)
    predicoes = np.argmax(probabilidades, axis=1)

    matriz = np.zeros((NUM_DIGITS, NUM_DIGITS), dtype=np.int64)
    for esperado, predito in zip(y_test, predicoes):
        matriz[int(esperado), int(predito)] += 1
    return matriz


def formatar_matriz_confusao(matriz: np.ndarray) -> str:
    linhas = ["          pred: " + " ".join(f"{digito:5d}" for digito in range(NUM_DIGITS))]
    for digito, valores in enumerate(matriz):
        linhas.append(
            f"real {digito:2d}: "
            + " ".join(f"{int(valor):5d}" for valor in valores)
        )
    return "\n".join(linhas)


def resumo_modelo(modelo: Any) -> str:
    linhas: list[str] = []
    modelo.summary(print_fn=linhas.append)
    return "\n".join(linhas)


def escrever_relatorio(
    caminho: Path,
    modelo: Any,
    history: Any,
    metricas_treino: dict[str, float],
    metricas_validacao: dict[str, float],
    metricas_teste: dict[str, float],
    matriz: np.ndarray,
    args: argparse.Namespace,
    saida_modelo: Path,
    usar_augmentation: bool,
) -> None:
    val_accuracy = history.history.get("val_accuracy", [])
    if val_accuracy:
        melhor_epoca = int(np.argmax(val_accuracy)) + 1
        melhor_val_accuracy = float(max(val_accuracy))
    else:
        melhor_epoca = len(history.epoch)
        melhor_val_accuracy = metricas_validacao["accuracy"]

    texto = f"""Modelo SOTA MNIST - relatorio de treinamento

Data/hora do treinamento: {datetime.now().astimezone().isoformat(timespec="seconds")}

Observacao:
  Este modelo e usado apenas como referencia software no trace_benchmark.py.
  Ele nao gera VHDL, nao altera pesos FPGA e nao faz parte do hardware.

Caminho do modelo salvo:
  {saida_modelo}

Hiperparametros principais:
  Epocas solicitadas       : {args.epochs}
  Epocas executadas        : {len(history.epoch)}
  Melhor epoca             : {melhor_epoca}
  Melhor val_accuracy      : {melhor_val_accuracy:.6f}
  Batch size               : {args.batch_size}
  Seed                     : {args.seed}
  Validation split         : {VALIDATION_SPLIT:.2f}
  Learning rate inicial    : {LEARNING_RATE:.6g}
  Data augmentation        : {"ligado" if usar_augmentation else "desligado"}
  Callbacks                : ModelCheckpoint, EarlyStopping, ReduceLROnPlateau

Metricas finais:
  Treino     loss={metricas_treino["loss"]:.6f} accuracy={metricas_treino["accuracy"]:.6f}
  Validacao  loss={metricas_validacao["loss"]:.6f} accuracy={metricas_validacao["accuracy"]:.6f}
  Teste      loss={metricas_teste["loss"]:.6f} accuracy={metricas_teste["accuracy"]:.6f}

Matriz de confusao no teste:
{formatar_matriz_confusao(matriz)}

Arquitetura resumida:
{resumo_modelo(modelo)}
"""

    caminho.write_text(texto, encoding="utf-8")


def parse_args(argv: list[str]) -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent

    parser = argparse.ArgumentParser(
        description=(
            "Treina uma CNN SOTA de referencia para MNIST, usada apenas pelo "
            "trace_benchmark.py como comparador software."
        )
    )
    parser.add_argument(
        "--epochs",
        type=int,
        default=DEFAULT_EPOCHS,
        help=f"Epocas de treinamento. Padrao: {DEFAULT_EPOCHS}.",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=DEFAULT_BATCH_SIZE,
        help=f"Batch size do treinamento. Padrao: {DEFAULT_BATCH_SIZE}.",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=DEFAULT_SEED,
        help=f"Seed para reprodutibilidade. Padrao: {DEFAULT_SEED}.",
    )
    parser.add_argument(
        "--saida-modelo",
        default=str(script_dir / "sota_mnist.keras"),
        help="Caminho do modelo .keras de saida. Padrao: python/sota_mnist.keras.",
    )
    parser.add_argument(
        "--saida-stats",
        default=str(script_dir / "sota_mnist_stats.txt"),
        help="Caminho do relatorio textual. Padrao: python/sota_mnist_stats.txt.",
    )
    parser.add_argument(
        "--no-augmentation",
        action="store_true",
        help="Desliga data augmentation durante o treinamento.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Sobrescreve modelo/stats existentes sem perguntar.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    validar_argumentos(args)

    saida_modelo = Path(args.saida_modelo).resolve()
    saida_stats = Path(args.saida_stats).resolve()
    validar_saidas(saida_modelo, saida_stats, args.force)

    configurar_seed(tf, args.seed)

    print("Carregando MNIST...")
    x_train_full, y_train_full, x_test, y_test = carregar_mnist(tf)
    x_train, y_train, x_val, y_val = separar_validacao(
        x_train_full,
        y_train_full,
        args.seed,
    )

    usar_augmentation = not args.no_augmentation
    print("Criando modelo CNN SOTA de referencia...")
    modelo = criar_modelo(tf, usar_augmentation=usar_augmentation, seed=args.seed)

    print("Treinando modelo...")
    history = modelo.fit(
        x_train,
        y_train,
        epochs=args.epochs,
        batch_size=args.batch_size,
        validation_data=(x_val, y_val),
        shuffle=True,
        verbose=2,
        callbacks=criar_callbacks(tf, saida_modelo),
    )

    print("Avaliando treino, validacao e teste...")
    metricas_treino = avaliar_modelo(modelo, x_train, y_train, args.batch_size)
    metricas_validacao = avaliar_modelo(modelo, x_val, y_val, args.batch_size)
    metricas_teste = avaliar_modelo(modelo, x_test, y_test, args.batch_size)
    matriz = matriz_confusao(modelo, x_test, y_test, args.batch_size)

    modelo.save(str(saida_modelo))
    escrever_relatorio(
        saida_stats,
        modelo,
        history,
        metricas_treino,
        metricas_validacao,
        metricas_teste,
        matriz,
        args,
        saida_modelo,
        usar_augmentation,
    )

    print("\nModelo SOTA salvo:")
    print(f"  - {saida_modelo}")
    print("Relatorio salvo:")
    print(f"  - {saida_stats}")
    print("\nMetricas finais:")
    print(
        f"  teste accuracy={metricas_teste['accuracy']:.4f} "
        f"loss={metricas_teste['loss']:.4f}"
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

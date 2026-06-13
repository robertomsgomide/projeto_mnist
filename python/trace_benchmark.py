#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
trace_benchmark.py

GUI PySide6 para comparar, de forma interativa, o impacto das configuracoes de
traco nos dois classificadores MNIST implementados pelo projeto.

O pre-processamento e importado de gui_layout.py. A classificacao e executada
localmente com o modelo denso .keras e as mascaras binarias .npy.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Sequence

import numpy as np
import tensorflow as tf

from PySide6.QtCore import QEvent, QPointF, QSignalBlocker, Qt, Signal
from PySide6.QtGui import QImage, QMouseEvent, QPainter, QPaintEvent, QPixmap
from PySide6.QtWidgets import (
    QApplication,
    QCheckBox,
    QFrame,
    QGridLayout,
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QSlider,
    QStyle,
    QVBoxLayout,
    QWidget,
)

from gui_layout import (
    CANVAS_SIZE,
    GRID_HEIGHT,
    GRID_WIDTH,
    IMG_BITS,
    PRESSURE_WIDTH_MAX,
    PRESSURE_WIDTH_MIN,
    RELATIVE_REFERENCE_BBOX,
    STROKE_INTERPOLATION_SPACING,
    STROKE_INTENSITY,
    STROKE_WIDTH,
    Stroke,
    StrokePoint,
    StrokeSettings,
    ZERO_MATRIX,
    active_pixel_count,
    bbox_dimensions,
    effective_base_width,
    matrix_to_qimage,
    matrix_to_strings,
    preprocess_qimage_to_matrix,
    relative_max_width_for,
    relative_min_width_for,
    render_strokes_to_qimage,
    stroke_points_bbox,
)


NUM_DIGITS = 10
TOP_K = 64
PREVIEW_SCALE = 9
# Referencia conservadora: ~45% do canvas e o tamanho util esperado para
# preservar uma espessura parecida apos a normalizacao para 28x28.
RELATIVE_REFERENCE_BBOX_DEFAULT = RELATIVE_REFERENCE_BBOX

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_DENSE_MODEL = SCRIPT_DIR / "classificador_denso.keras"
DEFAULT_BINARY_MODEL = SCRIPT_DIR / "classificador_binario.npy"
DEFAULT_SOTA_MODEL = SCRIPT_DIR / "sota_mnist.keras"
SOTA_MIN_CONFIDENCE = 0.70
SOTA_TRAIN_COMMAND = r".\.venv\Scripts\python.exe python\sota_mnist_gen.py --epochs 40"


class ArtifactLoadError(ValueError):
    """Indica que os artefatos software nao representam os modelos esperados."""


class SotaModelLoadError(RuntimeError):
    """Indica que o modelo SOTA de referencia nao pode ser carregado."""


@dataclass(frozen=True)
class ModelArtifacts:
    dense_weights: tuple[tuple[float, ...], ...]
    dense_biases: tuple[float, ...]
    top64_masks: tuple[tuple[int, ...], ...]

    def __post_init__(self) -> None:
        if len(self.dense_weights) != IMG_BITS:
            raise ArtifactLoadError(
                f"modelo denso deve conter {IMG_BITS} linhas de pesos; "
                f"recebido {len(self.dense_weights)}"
            )
        for pixel, weights in enumerate(self.dense_weights):
            if len(weights) != NUM_DIGITS:
                raise ArtifactLoadError(
                    f"pixel {pixel} do modelo denso deve conter {NUM_DIGITS} pesos"
                )

        if len(self.dense_biases) != NUM_DIGITS:
            raise ArtifactLoadError(
                f"modelo denso deve conter {NUM_DIGITS} biases; "
                f"recebido {len(self.dense_biases)}"
            )

        if len(self.top64_masks) != NUM_DIGITS:
            raise ArtifactLoadError(
                f"classificador binario deve conter {NUM_DIGITS} mascaras; "
                f"recebido {len(self.top64_masks)}"
            )
        for digit, mask in enumerate(self.top64_masks):
            if len(mask) != TOP_K:
                raise ArtifactLoadError(
                    f"mascara do digito {digit} deve conter {TOP_K} indices"
                )
            if any(index < 0 or index >= IMG_BITS for index in mask):
                raise ArtifactLoadError(
                    f"mascara do digito {digit} contem indice fora de 0..{IMG_BITS - 1}"
                )


@dataclass(frozen=True)
class Prediction:
    digit: int
    scores: tuple[float, ...]


@dataclass(frozen=True)
class SotaPrediction:
    digit: int
    confidence: float
    probabilities: tuple[float, ...]


@dataclass(frozen=True)
class ClassificationResults:
    dense: Prediction
    binary: Prediction
    sota: SotaPrediction


@dataclass(frozen=True)
class BenchmarkStats:
    total: int = 0
    dense_correct: int = 0
    binary_correct: int = 0
    last_dense: int | None = None
    last_binary: int | None = None
    last_sota_digit: int | None = None
    last_sota_confidence: float | None = None


def extract_dense_weights_from_model(modelo: Any) -> tuple[np.ndarray, np.ndarray, str]:
    descricoes: list[str] = []
    for camada in modelo.layers:
        pesos = camada.get_weights()
        if len(pesos) != 2:
            continue

        w, b = pesos
        if w.shape == (IMG_BITS, NUM_DIGITS) and b.shape == (NUM_DIGITS,):
            return (
                np.asarray(w, dtype=np.float32),
                np.asarray(b, dtype=np.float32),
                camada.name,
            )

    for camada in modelo.layers:
        pesos = camada.get_weights()
        if pesos:
            descricoes.append(f"{camada.name}: {[tuple(p.shape) for p in pesos]}")

    detalhe = "\n  - ".join(descricoes) if descricoes else "nenhuma camada com pesos"
    raise ArtifactLoadError(
        "Modelo denso nao contem uma camada compativel com Dense(784, 10):\n"
        f"  - {detalhe}"
    )


def load_dense_model_artifact(
    caminho: Path,
) -> tuple[tuple[tuple[float, ...], ...], tuple[float, ...]]:
    if not caminho.exists():
        raise ArtifactLoadError(
            "Modelo denso nao encontrado:\n"
            f"  {caminho}\n\n"
            "Gere-o com gerar_pesos.py --salvar-modelo e mova o arquivo para SCRIPT_DIR."
        )

    try:
        modelo = tf.keras.models.load_model(str(caminho), compile=False)
    except Exception as exc:
        raise ArtifactLoadError(
            "Falha ao carregar modelo denso:\n"
            f"  {caminho}\n\n"
            f"Detalhe original: {exc}"
        ) from exc

    w, b, _nome_camada = extract_dense_weights_from_model(modelo)
    dense_weights = tuple(
        tuple(float(w[pixel, digit]) for digit in range(NUM_DIGITS))
        for pixel in range(IMG_BITS)
    )
    dense_biases = tuple(float(b[digit]) for digit in range(NUM_DIGITS))
    return dense_weights, dense_biases


def load_binary_model_artifact(caminho: Path) -> tuple[tuple[int, ...], ...]:
    if not caminho.exists():
        raise ArtifactLoadError(
            "Classificador binario nao encontrado:\n"
            f"  {caminho}\n\n"
            "Gere-o com gerar_pesos.py --salvar-modelo e mova o arquivo para SCRIPT_DIR."
        )

    try:
        indices = np.load(str(caminho), allow_pickle=False)
    except Exception as exc:
        raise ArtifactLoadError(
            "Falha ao carregar classificador binario:\n"
            f"  {caminho}\n\n"
            f"Detalhe original: {exc}"
        ) from exc

    if indices.shape != (NUM_DIGITS, TOP_K):
        raise ArtifactLoadError(
            "classificador_binario.npy deve ter formato "
            f"{(NUM_DIGITS, TOP_K)}; recebido {indices.shape}"
        )
    if not np.issubdtype(indices.dtype, np.integer):
        raise ArtifactLoadError("classificador_binario.npy deve conter indices inteiros")

    return tuple(
        tuple(int(indices[digit, index]) for index in range(TOP_K))
        for digit in range(NUM_DIGITS)
    )


def load_project_artifacts(
    dense_model_path: Path = DEFAULT_DENSE_MODEL,
    binary_model_path: Path = DEFAULT_BINARY_MODEL,
) -> ModelArtifacts:
    dense_weights, dense_biases = load_dense_model_artifact(dense_model_path)
    top64_masks = load_binary_model_artifact(binary_model_path)

    return ModelArtifacts(
        dense_weights=dense_weights,
        dense_biases=dense_biases,
        top64_masks=top64_masks,
    )

def load_sota_model(caminho: Path = DEFAULT_SOTA_MODEL) -> Any:
    if not caminho.exists():
        raise SotaModelLoadError(
            "Modelo SOTA de referencia nao encontrado:\n"
            f"  {caminho}\n\n"
            "Treine o modelo antes de iniciar o benchmark:\n"
            f"  {SOTA_TRAIN_COMMAND}"
        )

    try:
        return tf.keras.models.load_model(str(caminho), compile=False)
    except Exception as exc:
        raise SotaModelLoadError(
            "Falha ao carregar o modelo SOTA de referencia:\n"
            f"  {caminho}\n\n"
            f"Detalhe original: {exc}"
        ) from exc


def _matrix_to_flat_bits(matrix: Iterable[Any]) -> tuple[int, ...]:
    rows = matrix_to_strings(matrix)
    return tuple(1 if value == "1" else 0 for row in rows for value in row)


def matrix_to_sota_input(matrix: Iterable[Any]) -> Any:
    rows = matrix_to_strings(matrix)
    array = np.array(
        [[1.0 if value == "1" else 0.0 for value in row] for row in rows],
        dtype=np.float32,
    )
    return array.reshape((1, GRID_HEIGHT, GRID_WIDTH, 1))


def argmax_first(scores: Sequence[float]) -> int:
    if not scores:
        raise ValueError("scores nao pode ser vazio")
    return max(range(len(scores)), key=lambda index: scores[index])


def classify_dense(matrix: Iterable[Any], artifacts: ModelArtifacts) -> Prediction:
    flat = _matrix_to_flat_bits(matrix)
    scores = list(artifacts.dense_biases)

    for pixel, active in enumerate(flat):
        if not active:
            continue
        weights = artifacts.dense_weights[pixel]
        for digit in range(NUM_DIGITS):
            scores[digit] += weights[digit]

    return Prediction(digit=argmax_first(scores), scores=tuple(scores))


def classify_binary(matrix: Iterable[Any], artifacts: ModelArtifacts) -> Prediction:
    flat = _matrix_to_flat_bits(matrix)
    scores = tuple(
        sum(flat[pixel] for pixel in artifacts.top64_masks[digit])
        for digit in range(NUM_DIGITS)
    )
    return Prediction(digit=argmax_first(scores), scores=scores)


def classify_sota(matrix: Iterable[Any], sota_model: Any) -> SotaPrediction:
    batch = matrix_to_sota_input(matrix)
    raw_probabilities = sota_model.predict(batch, verbose=0)
    probabilities_array = np.asarray(raw_probabilities, dtype=np.float32).reshape(-1)

    if probabilities_array.shape != (NUM_DIGITS,):
        raise SotaModelLoadError(
            "Modelo SOTA retornou vetor de probabilidades invalido: "
            f"{probabilities_array.shape}; esperado {(NUM_DIGITS,)}."
        )

    digit = int(np.argmax(probabilities_array))
    confidence = float(probabilities_array[digit])
    probabilities = tuple(float(value) for value in probabilities_array)
    return SotaPrediction(
        digit=digit,
        confidence=confidence,
        probabilities=probabilities,
    )


def classify_matrix(
    matrix: Iterable[Any],
    artifacts: ModelArtifacts,
    sota_model: Any,
) -> ClassificationResults:
    return ClassificationResults(
        dense=classify_dense(matrix, artifacts),
        binary=classify_binary(matrix, artifacts),
        sota=classify_sota(matrix, sota_model),
    )


def reset_stats() -> BenchmarkStats:
    return BenchmarkStats()


def record_classification(
    stats: BenchmarkStats,
    results: ClassificationResults,
    contabilizar: bool,
) -> BenchmarkStats:
    total = stats.total + (1 if contabilizar else 0)
    dense_correct = stats.dense_correct
    binary_correct = stats.binary_correct

    if contabilizar:
        referencia = results.sota.digit
        dense_correct += 1 if results.dense.digit == referencia else 0
        binary_correct += 1 if results.binary.digit == referencia else 0

    return BenchmarkStats(
        total=total,
        dense_correct=dense_correct,
        binary_correct=binary_correct,
        last_dense=results.dense.digit,
        last_binary=results.binary.digit,
        last_sota_digit=results.sota.digit,
        last_sota_confidence=results.sota.confidence,
    )


def accuracy_text(correct: int, total: int) -> str:
    percentage = 0.0 if total == 0 else 100.0 * correct / total
    return f"{correct} / {total} ({percentage:.1f}%)"


def confidence_text(confidence: float) -> str:
    return f"{100.0 * confidence:.1f}%"


def sota_result_text(digit: int | None, confidence: float | None) -> str:
    if digit is None or confidence is None:
        return "-"
    return f"{digit} ({confidence_text(confidence)})"


def print_stroke_diagnostics(
    strokes: Iterable[Iterable[StrokePoint]],
    settings: StrokeSettings,
    matrix: Iterable[Any],
) -> None:
    bbox = stroke_points_bbox(strokes)
    base_width = effective_base_width(settings, bbox)

    if bbox is None:
        bbox_text = "-"
    else:
        bbox_width, bbox_height = bbox_dimensions(bbox)
        bbox_text = f"{bbox_width:.1f}x{bbox_height:.1f}"

    density = 100.0 * active_pixel_count(matrix) / IMG_BITS
    print(f"bbox: {bbox_text}")
    print(f"largura efetiva: {base_width:.2f} px")
    print(f"anti-aliasing: {100.0 * settings.antialiasing:.0f}%")
    print(f"densidade 28x28: {density:.1f}%")


class DrawingCanvas(QWidget):
    changed = Signal()

    def __init__(
        self,
        settings: StrokeSettings = StrokeSettings(),
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self.setFixedSize(CANVAS_SIZE, CANVAS_SIZE)
        self.setMouseTracking(True)
        self.setAutoFillBackground(False)
        self.setStyleSheet("border: 1px solid #888;")

        self.settings = settings
        self.image = QImage(CANVAS_SIZE, CANVAS_SIZE, QImage.Format.Format_RGB32)
        self.image.fill(Qt.GlobalColor.white)

        self.pointer_down = False
        self.strokes: list[Stroke] = []
        self.current_stroke: Stroke | None = None

    def clear(self) -> None:
        self.pointer_down = False
        self.strokes = []
        self.current_stroke = None
        self.image.fill(Qt.GlobalColor.white)
        self.changed.emit()
        self.update()

    def set_settings(self, settings: StrokeSettings) -> None:
        self.settings = settings
        self._rerender()

    def is_empty(self) -> bool:
        return not self.strokes

    def render_preprocess_image(self) -> QImage:
        return render_strokes_to_qimage(self.strokes, self.settings)

    def _rerender(self) -> None:
        self.image = self.render_preprocess_image()
        self.changed.emit()
        self.update()

    def _finish_stroke(self) -> None:
        self.pointer_down = False
        self.current_stroke = None

    def paintEvent(self, event: QPaintEvent) -> None:
        painter = QPainter(self)
        painter.drawImage(0, 0, self.image)
        painter.end()
        super().paintEvent(event)

    def mousePressEvent(self, event: QMouseEvent) -> None:
        if event.button() == Qt.MouseButton.LeftButton:
            self.pointer_down = True
            self._handle_point(event.position(), 1.0)
            event.accept()

    def mouseMoveEvent(self, event: QMouseEvent) -> None:
        if self.pointer_down:
            self._handle_point(event.position(), 1.0)
            event.accept()

    def mouseReleaseEvent(self, event: QMouseEvent) -> None:
        if event.button() == Qt.MouseButton.LeftButton:
            self._finish_stroke()
            event.accept()

    def tabletEvent(self, event: Any) -> None:
        event_type = event.type()
        if event_type == QEvent.Type.TabletPress:
            self.pointer_down = True
            self._handle_point(event.position(), float(event.pressure() or 1.0))
            event.accept()
            return

        if event_type == QEvent.Type.TabletMove:
            pressure = float(event.pressure() or 0.0)
            if not self.pointer_down and pressure <= 0.0:
                self.current_stroke = None
                event.accept()
                return
            self.pointer_down = True
            self._handle_point(event.position(), pressure)
            event.accept()
            return

        if event_type == QEvent.Type.TabletRelease:
            self._finish_stroke()
            event.accept()
            return

        super().tabletEvent(event)

    def _handle_point(self, pos: QPointF, pressure: float) -> None:
        if not self.rect().contains(pos.toPoint()):
            self.current_stroke = None
            return

        clamped_pressure = max(0.0, min(1.0, pressure))
        if self.current_stroke is None:
            self.current_stroke = []
            self.strokes.append(self.current_stroke)

        self.current_stroke.append((QPointF(pos), clamped_pressure))
        self._rerender()


class TraceBenchmarkApp(QMainWindow):
    def __init__(
        self,
        artifacts: ModelArtifacts | None = None,
        sota_model: Any | None = None,
    ) -> None:
        super().__init__()
        self.setWindowTitle("MNIST Trace Benchmark")
        self.setWindowIcon(self.style().standardIcon(QStyle.StandardPixmap.SP_ComputerIcon))

        self.artifacts = artifacts if artifacts is not None else load_project_artifacts()
        self.sota_model = sota_model if sota_model is not None else load_sota_model()
        self.settings = StrokeSettings()
        self.stats = reset_stats()
        self.last_matrix = list(ZERO_MATRIX)
        self.sliders: dict[str, QSlider] = {}
        self.slider_value_labels: dict[str, QLabel] = {}

        self._build_ui()
        self._refresh_slider_value_labels()
        self._update_preview(ZERO_MATRIX)
        self._refresh_stats_labels()
        self.message_label.setText("Pronto para iniciar o benchmark.")

    def _build_ui(self) -> None:
        central = QWidget(self)
        self.setCentralWidget(central)

        root = QHBoxLayout(central)
        root.setContentsMargins(12, 12, 12, 12)
        root.setSpacing(12)

        left = QVBoxLayout()
        left.setSpacing(8)
        root.addLayout(left)

        self.canvas = DrawingCanvas(self.settings)
        left.addWidget(self.canvas)

        self.message_label = QLabel()
        self.message_label.setWordWrap(True)
        self.message_label.setFixedWidth(CANVAS_SIZE)
        self.message_label.setAlignment(
            Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignTop
        )
        left.addWidget(self.message_label)
        left.addStretch(1)

        side = QVBoxLayout()
        side.setSpacing(8)
        root.addLayout(side)

        self.prompt_label = QLabel("Escreva um digito")
        font = self.prompt_label.font()
        font.setPointSize(18)
        font.setBold(True)
        self.prompt_label.setFont(font)
        side.addWidget(self.prompt_label)

        button_layout = QHBoxLayout()
        self.clear_button = QPushButton("APAGAR")
        self.classify_button = QPushButton("CLASSIFICA")
        self.clear_button.clicked.connect(self.on_clear)
        self.classify_button.clicked.connect(self.on_classify)
        button_layout.addWidget(self.clear_button)
        button_layout.addWidget(self.classify_button)
        side.addLayout(button_layout)

        results_box = QFrame()
        results_box.setFrameShape(QFrame.Shape.StyledPanel)
        results_layout = QGridLayout(results_box)
        self.sota_result_label = QLabel("-")
        self.dense_result_label = QLabel("-")
        self.binary_result_label = QLabel("-")
        self.dense_stats_label = QLabel("0 / 0 (0.0%)")
        self.binary_stats_label = QLabel("0 / 0 (0.0%)")
        results_layout.addWidget(QLabel("Referencia SOTA:"), 0, 0)
        results_layout.addWidget(self.sota_result_label, 0, 1)
        results_layout.addWidget(QLabel("Denso:"), 1, 0)
        results_layout.addWidget(self.dense_result_label, 1, 1)
        results_layout.addWidget(QLabel("Binario:"), 2, 0)
        results_layout.addWidget(self.binary_result_label, 2, 1)
        results_layout.addWidget(QLabel("Denso vs SOTA:"), 3, 0)
        results_layout.addWidget(self.dense_stats_label, 3, 1)
        results_layout.addWidget(QLabel("Binario vs SOTA:"), 4, 0)
        results_layout.addWidget(self.binary_stats_label, 4, 1)
        side.addWidget(results_box)

        settings_box = QFrame()
        settings_box.setFrameShape(QFrame.Shape.StyledPanel)
        settings_layout = QGridLayout(settings_box)
        settings_layout.addWidget(QLabel("Configuracoes do traco"), 0, 0, 1, 3)
        self._add_slider(settings_layout, 1, "base_width", "Largura base", 4, 60, round(STROKE_WIDTH))
        self._add_slider(settings_layout, 2, "pressure_min", "Pressao minima", 10, 150, round(PRESSURE_WIDTH_MIN * 100))
        self._add_slider(settings_layout, 3, "pressure_max", "Pressao maxima", 10, 200, round(PRESSURE_WIDTH_MAX * 100))
        self._add_slider(settings_layout, 4, "intensity", "Intensidade", 5, 100, round(STROKE_INTENSITY * 100))
        self._add_slider(settings_layout, 5, "antialiasing", "Anti-aliasing", 0, 100, 100)
        self._add_slider(settings_layout, 6, "spacing", "Interpolacao", 10, 150, round(STROKE_INTERPOLATION_SPACING * 100))
        self.relative_width_checkbox = QCheckBox("Espessura relativa")
        self.relative_width_checkbox.setChecked(self.settings.relative_width_enabled)
        self.relative_width_checkbox.toggled.connect(self.on_relative_width_changed)
        settings_layout.addWidget(self.relative_width_checkbox, 7, 0, 1, 3)
        side.addWidget(settings_box)

        preview_title = QLabel("Ultima matriz normalizada 28x28")
        side.addWidget(preview_title)
        self.preview_label = QLabel()
        self.preview_label.setFixedSize(GRID_WIDTH * PREVIEW_SCALE, GRID_HEIGHT * PREVIEW_SCALE)
        self.preview_label.setFrameShape(QFrame.Shape.StyledPanel)
        self.preview_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        side.addWidget(self.preview_label)

        side.addStretch(1)

    def _add_slider(
        self,
        layout: QGridLayout,
        row: int,
        key: str,
        title: str,
        minimum: int,
        maximum: int,
        value: int,
    ) -> None:
        slider = QSlider(Qt.Orientation.Horizontal)
        slider.setRange(minimum, maximum)
        slider.setValue(value)
        value_label = QLabel()
        value_label.setMinimumWidth(72)
        value_label.setAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)
        slider.valueChanged.connect(lambda _value, changed_key=key: self.on_slider_changed(changed_key))

        self.sliders[key] = slider
        self.slider_value_labels[key] = value_label
        layout.addWidget(QLabel(title + ":"), row, 0)
        layout.addWidget(slider, row, 1)
        layout.addWidget(value_label, row, 2)

    def _set_slider_without_signal(self, key: str, value: int) -> None:
        slider = self.sliders[key]
        blocker = QSignalBlocker(slider)
        slider.setValue(value)
        del blocker

    def _settings_from_sliders(self) -> StrokeSettings:
        base_width = float(self.sliders["base_width"].value())
        return StrokeSettings(
            base_width=base_width,
            pressure_width_min=self.sliders["pressure_min"].value() / 100.0,
            pressure_width_max=self.sliders["pressure_max"].value() / 100.0,
            intensity=self.sliders["intensity"].value() / 100.0,
            antialiasing=self.sliders["antialiasing"].value() / 100.0,
            interpolation_spacing=self.sliders["spacing"].value() / 100.0,
            relative_width_enabled=self.relative_width_checkbox.isChecked(),
            relative_reference_bbox=RELATIVE_REFERENCE_BBOX_DEFAULT,
            relative_min_width=relative_min_width_for(base_width),
            relative_max_width=relative_max_width_for(base_width),
        )

    def _refresh_slider_value_labels(self) -> None:
        base_suffix = " px ref" if self.relative_width_checkbox.isChecked() else " px"
        self.slider_value_labels["base_width"].setText(
            f"{self.sliders['base_width'].value()}{base_suffix}"
        )
        self.slider_value_labels["pressure_min"].setText(
            f"{self.sliders['pressure_min'].value() / 100.0:.2f}"
        )
        self.slider_value_labels["pressure_max"].setText(
            f"{self.sliders['pressure_max'].value() / 100.0:.2f}"
        )
        self.slider_value_labels["intensity"].setText(
            f"{self.sliders['intensity'].value()}%"
        )
        self.slider_value_labels["antialiasing"].setText(
            f"{self.sliders['antialiasing'].value()}%"
        )
        self.slider_value_labels["spacing"].setText(
            f"{self.sliders['spacing'].value() / 100.0:.2f}"
        )

    def _apply_settings_change(self) -> None:
        self._refresh_slider_value_labels()
        self.settings = self._settings_from_sliders()
        self.canvas.set_settings(self.settings)
        self.reset_benchmark()
        self.message_label.setText(
            "Configuracoes alteradas; estatisticas reiniciadas."
        )

    def _refresh_stats_labels(self) -> None:
        dense_text = "-" if self.stats.last_dense is None else str(self.stats.last_dense)
        binary_text = "-" if self.stats.last_binary is None else str(self.stats.last_binary)
        sota_text = sota_result_text(
            self.stats.last_sota_digit,
            self.stats.last_sota_confidence,
        )

        self.prompt_label.setText("Escreva um digito")
        self.sota_result_label.setText(sota_text)
        self.dense_result_label.setText(dense_text)
        self.binary_result_label.setText(binary_text)
        self.dense_stats_label.setText(
            accuracy_text(self.stats.dense_correct, self.stats.total)
        )
        self.binary_stats_label.setText(
            accuracy_text(self.stats.binary_correct, self.stats.total)
        )

    def _update_preview(self, matrix: Iterable[Any]) -> None:
        self.last_matrix = matrix_to_strings(matrix)
        image = matrix_to_qimage(self.last_matrix, PREVIEW_SCALE)
        self.preview_label.setPixmap(QPixmap.fromImage(image))

    def reset_benchmark(self) -> None:
        self.stats = reset_stats()
        self.canvas.clear()
        self._update_preview(ZERO_MATRIX)
        self._refresh_stats_labels()

    def on_slider_changed(self, changed_key: str) -> None:
        pressure_min = self.sliders["pressure_min"].value()
        pressure_max = self.sliders["pressure_max"].value()
        if changed_key == "pressure_min" and pressure_min > pressure_max:
            self._set_slider_without_signal("pressure_max", pressure_min)
        elif changed_key == "pressure_max" and pressure_max < pressure_min:
            self._set_slider_without_signal("pressure_min", pressure_max)

        self._apply_settings_change()

    def on_relative_width_changed(self, _checked: bool) -> None:
        self._apply_settings_change()

    def on_clear(self) -> None:
        self.canvas.clear()
        self.message_label.setText("Canvas apagado. Estatisticas preservadas.")

    def on_classify(self) -> bool:
        matrix, status = preprocess_qimage_to_matrix(
            self.canvas.render_preprocess_image()
        )
        if matrix is None:
            self.message_label.setText(f"Classificacao ignorada: {status}.")
            return False

        print_stroke_diagnostics(self.canvas.strokes, self.settings, matrix)

        try:
            results = classify_matrix(matrix, self.artifacts, self.sota_model)
        except SotaModelLoadError as exc:
            self.message_label.setText(f"Classificacao SOTA falhou: {exc}")
            return False

        contabilizar = results.sota.confidence >= SOTA_MIN_CONFIDENCE
        self.stats = record_classification(
            self.stats,
            results,
            contabilizar,
        )
        self._update_preview(matrix)
        self.canvas.clear()
        self._refresh_stats_labels()

        sota_label = (
            f"SOTA {results.sota.digit} "
            f"({confidence_text(results.sota.confidence)})"
        )
        resultado_label = (
            f"{sota_label}; denso {results.dense.digit}; "
            f"binario {results.binary.digit}."
        )
        if contabilizar:
            self.message_label.setText(resultado_label)
        else:
            self.message_label.setText(
                "Amostra ignorada: SOTA pouco confiante. "
                f"{resultado_label}"
            )
        return True


def main() -> int:
    app = QApplication(sys.argv)
    try:
        window = TraceBenchmarkApp()
    except ArtifactLoadError as exc:
        QMessageBox.critical(
            None,
            "Erro ao carregar classificadores",
            str(exc),
        )
        return 1
    except SotaModelLoadError as exc:
        QMessageBox.critical(
            None,
            "Erro ao carregar modelo SOTA",
            str(exc),
        )
        return 1

    window.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())

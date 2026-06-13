#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gui_layout.py

Configuracoes e primitivas compartilhadas pelas GUIs MNIST do projeto.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, replace
from typing import Any, Iterable

from PySide6.QtCore import QPointF, Qt
from PySide6.QtGui import QColor, QImage, QPainter, QPen


CANVAS_SIZE = 560
GRID_WIDTH = 28
GRID_HEIGHT = 28
IMG_BITS = GRID_WIDTH * GRID_HEIGHT

STROKE_WIDTH = 44
MNIST_INNER_SIZE = 20
NORMALIZE_MARGIN = (GRID_WIDTH - MNIST_INNER_SIZE) // 2
DARK_PIXEL_THRESHOLD = 220
INK_DETECT_THRESHOLD = 0.05
BINARIZE_THRESHOLD = 0.3
PRESSURE_WIDTH_MIN = 0.12
PRESSURE_WIDTH_MAX = 1.0
STROKE_INTERPOLATION_SPACING = 0.45
STROKE_INTENSITY = 1.0
RELATIVE_WIDTH_ENABLED = True
RELATIVE_REFERENCE_BBOX = CANVAS_SIZE * 0.45
RELATIVE_MIN_WIDTH_SCALE = 0.35
RELATIVE_MAX_WIDTH_SCALE = 1.80
SNAPSHOT_SCALE = 12

ZERO_MATRIX = ["0" * GRID_WIDTH for _ in range(GRID_HEIGHT)]
StrokePoint = tuple[QPointF, float]
Stroke = list[StrokePoint]
StrokeBBox = tuple[float, float, float, float]


def relative_min_width_for(base_width: float) -> float:
    return max(1.0, base_width * RELATIVE_MIN_WIDTH_SCALE)


def relative_max_width_for(base_width: float) -> float:
    return max(relative_min_width_for(base_width), base_width * RELATIVE_MAX_WIDTH_SCALE)


@dataclass(frozen=True)
class StrokeSettings:
    base_width: float = float(STROKE_WIDTH)
    pressure_width_min: float = float(PRESSURE_WIDTH_MIN)
    pressure_width_max: float = float(PRESSURE_WIDTH_MAX)
    intensity: float = float(STROKE_INTENSITY)
    antialiasing: float = 1.0
    interpolation_spacing: float = float(STROKE_INTERPOLATION_SPACING)
    relative_width_enabled: bool = bool(RELATIVE_WIDTH_ENABLED)
    relative_reference_bbox: float = float(RELATIVE_REFERENCE_BBOX)
    relative_min_width: float = relative_min_width_for(float(STROKE_WIDTH))
    relative_max_width: float = relative_max_width_for(float(STROKE_WIDTH))

    def __post_init__(self) -> None:
        if self.base_width <= 0.0:
            raise ValueError("base_width deve ser positivo")
        if self.pressure_width_min <= 0.0 or self.pressure_width_max <= 0.0:
            raise ValueError("multiplicadores de pressao devem ser positivos")
        if self.pressure_width_min > self.pressure_width_max:
            raise ValueError("pressao minima nao pode superar pressao maxima")
        if not 0.0 < self.intensity <= 1.0:
            raise ValueError("intensity deve estar em 0.0 < valor <= 1.0")
        if not 0.0 <= self.antialiasing <= 1.0:
            raise ValueError("antialiasing deve estar em 0.0 <= valor <= 1.0")
        if self.interpolation_spacing <= 0.0:
            raise ValueError("interpolation_spacing deve ser positivo")
        if self.relative_reference_bbox <= 0.0:
            raise ValueError("relative_reference_bbox deve ser positivo")
        if self.relative_min_width <= 0.0 or self.relative_max_width <= 0.0:
            raise ValueError("limites de espessura relativa devem ser positivos")
        if self.relative_min_width > self.relative_max_width:
            raise ValueError("relative_min_width nao pode superar relative_max_width")


DEFAULT_STROKE_SETTINGS = StrokeSettings()


def stroke_settings_for_base_width(
    base_width: float,
    settings: StrokeSettings = DEFAULT_STROKE_SETTINGS,
) -> StrokeSettings:
    return replace(
        settings,
        base_width=base_width,
        relative_min_width=relative_min_width_for(base_width),
        relative_max_width=relative_max_width_for(base_width),
    )


def _normaliza_matriz(matrix: Iterable[Any]) -> list[list[int]]:
    rows: list[list[int]] = []

    for row in matrix:
        if isinstance(row, str):
            values = [1 if ch == "1" else 0 for ch in row.strip()]
        else:
            values = [1 if int(value) else 0 for value in row]

        rows.append(values)

    if len(rows) != GRID_HEIGHT:
        raise ValueError(f"matrix deve ter {GRID_HEIGHT} linhas")

    for index, row in enumerate(rows):
        if len(row) != GRID_WIDTH:
            raise ValueError(
                f"matrix linha {index} deve ter {GRID_WIDTH} colunas"
            )

        for value in row:
            if value not in (0, 1):
                raise ValueError("matrix deve conter somente 0/1")

    return rows


def matrix_to_strings(matrix: Iterable[Any]) -> list[str]:
    rows = _normaliza_matriz(matrix)
    return ["".join("1" if value else "0" for value in row) for row in rows]


def active_pixel_count(matrix: Iterable[Any]) -> int:
    return sum(row.count("1") for row in matrix_to_strings(matrix))


def _luminance_255(color: QColor) -> float:
    return (
        0.299 * color.red()
        + 0.587 * color.green()
        + 0.114 * color.blue()
    )


def _ink_intensity(color: QColor) -> float:
    luminance = _luminance_255(color) / 255.0
    return max(0.0, min(1.0, 1.0 - luminance))


def image_is_dark(color: QColor, threshold: int = DARK_PIXEL_THRESHOLD) -> bool:
    return _luminance_255(color) < threshold


def stroke_points_bbox(strokes: Iterable[Iterable[StrokePoint]]) -> StrokeBBox | None:
    min_x = math.inf
    min_y = math.inf
    max_x = -math.inf
    max_y = -math.inf
    found = False

    for stroke in strokes:
        for pos, _pressure in stroke:
            found = True
            min_x = min(min_x, pos.x())
            min_y = min(min_y, pos.y())
            max_x = max(max_x, pos.x())
            max_y = max(max_y, pos.y())

    if not found:
        return None
    return min_x, min_y, max_x, max_y


def bbox_dimensions(bbox: StrokeBBox) -> tuple[float, float]:
    min_x, min_y, max_x, max_y = bbox
    return max(0.0, max_x - min_x), max(0.0, max_y - min_y)


def clamp(value: float, minimum: float, maximum: float) -> float:
    return max(minimum, min(maximum, value))


def effective_base_width(
    settings: StrokeSettings,
    bbox: StrokeBBox | None,
) -> float:
    if not settings.relative_width_enabled or bbox is None:
        return settings.base_width

    bbox_width, bbox_height = bbox_dimensions(bbox)
    bbox_size = max(bbox_width, bbox_height)
    scale = bbox_size / settings.relative_reference_bbox
    effective = settings.base_width * scale
    return clamp(effective, settings.relative_min_width, settings.relative_max_width)


def stroke_width_for_pressure(
    settings: StrokeSettings,
    pressure: float,
    base_width: float,
) -> float:
    clamped = max(0.0, min(1.0, pressure))
    factor = (
        settings.pressure_width_min
        + (settings.pressure_width_max - settings.pressure_width_min) * clamped
    )
    return max(1.0, base_width * factor)


def default_stroke_width_for_pressure(
    pressure: float,
    base_width: float = STROKE_WIDTH,
) -> float:
    return stroke_width_for_pressure(
        stroke_settings_for_base_width(base_width),
        pressure,
        base_width,
    )


def _stroke_color(settings: StrokeSettings) -> QColor:
    gray = round(255 * (1.0 - settings.intensity))
    return QColor(gray, gray, gray)


def _draw_stroke(
    painter: QPainter,
    stroke: Stroke,
    settings: StrokeSettings,
    base_width: float,
) -> None:
    if not stroke:
        return

    color = _stroke_color(settings)
    first_pos, first_pressure = stroke[0]
    first_width = stroke_width_for_pressure(settings, first_pressure, base_width)

    painter.setPen(Qt.PenStyle.NoPen)
    painter.setBrush(color)
    radius = first_width / 2.0
    painter.drawEllipse(first_pos, radius, radius)

    pen = QPen(color)
    pen.setCapStyle(Qt.PenCapStyle.RoundCap)
    pen.setJoinStyle(Qt.PenJoinStyle.RoundJoin)

    start = first_pos
    start_pressure = first_pressure
    for pos, pressure in stroke[1:]:
        dx = pos.x() - start.x()
        dy = pos.y() - start.y()
        distance = math.hypot(dx, dy)
        average_width = (
            stroke_width_for_pressure(settings, start_pressure, base_width)
            + stroke_width_for_pressure(settings, pressure, base_width)
        ) / 2.0
        spacing = max(1.0, average_width * settings.interpolation_spacing)
        steps = max(1, math.ceil(distance / spacing))

        previous = start
        for step in range(1, steps + 1):
            t = step / steps
            current = QPointF(start.x() + dx * t, start.y() + dy * t)
            current_pressure = start_pressure + (pressure - start_pressure) * t
            pen.setWidthF(stroke_width_for_pressure(settings, current_pressure, base_width))
            painter.setPen(pen)
            painter.drawLine(previous, current)
            previous = current

        start = pos
        start_pressure = pressure


def _render_stroke_lists_to_qimage(
    stroke_lists: list[Stroke],
    settings: StrokeSettings,
    base_width: float,
    antialiasing: bool,
) -> QImage:
    image = QImage(CANVAS_SIZE, CANVAS_SIZE, QImage.Format.Format_RGB32)
    image.fill(Qt.GlobalColor.white)

    painter = QPainter(image)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing, antialiasing)
    for stroke in stroke_lists:
        _draw_stroke(painter, stroke, settings, base_width)
    painter.end()
    return image


def _coerce_stroke_settings(settings: StrokeSettings | float) -> StrokeSettings:
    if isinstance(settings, StrokeSettings):
        return settings
    return stroke_settings_for_base_width(float(settings))


def render_strokes_to_qimage(
    strokes: Iterable[Iterable[StrokePoint]],
    settings: StrokeSettings | float = DEFAULT_STROKE_SETTINGS,
) -> QImage:
    actual_settings = _coerce_stroke_settings(settings)
    stroke_lists = [list(stroke) for stroke in strokes]
    bbox = stroke_points_bbox(stroke_lists)
    base_width = effective_base_width(actual_settings, bbox)

    if actual_settings.antialiasing <= 0.0:
        return _render_stroke_lists_to_qimage(
            stroke_lists,
            actual_settings,
            base_width,
            False,
        )
    if actual_settings.antialiasing >= 1.0:
        return _render_stroke_lists_to_qimage(
            stroke_lists,
            actual_settings,
            base_width,
            True,
        )

    hard_image = _render_stroke_lists_to_qimage(
        stroke_lists,
        actual_settings,
        base_width,
        False,
    )
    smooth_image = _render_stroke_lists_to_qimage(
        stroke_lists,
        actual_settings,
        base_width,
        True,
    )

    painter = QPainter(hard_image)
    painter.setOpacity(actual_settings.antialiasing)
    painter.drawImage(0, 0, smooth_image)
    painter.end()
    return hard_image


def render_strokes_for_preprocess(strokes: Iterable[Iterable[StrokePoint]]) -> QImage:
    return render_strokes_to_qimage(strokes, DEFAULT_STROKE_SETTINGS)


def preprocess_qimage_to_matrix(image: QImage) -> tuple[list[str] | None, str]:
    """Normaliza o canvas high-res para matriz MNIST 28x28 binaria."""

    source = image.convertToFormat(QImage.Format.Format_RGB32)
    min_x = source.width()
    min_y = source.height()
    max_x = -1
    max_y = -1

    for y in range(source.height()):
        for x in range(source.width()):
            if _ink_intensity(source.pixelColor(x, y)) < INK_DETECT_THRESHOLD:
                continue
            min_x = min(min_x, x)
            min_y = min(min_y, y)
            max_x = max(max_x, x)
            max_y = max(max_y, y)

    if max_x < 0 or max_y < 0:
        return None, "canvas vazio"

    digit_width = max_x - min_x + 1
    digit_height = max_y - min_y + 1
    crop = source.copy(min_x, min_y, digit_width, digit_height)

    if MNIST_INNER_SIZE <= 0 or MNIST_INNER_SIZE > min(GRID_WIDTH, GRID_HEIGHT):
        raise ValueError("MNIST_INNER_SIZE invalido para grade 28x28")

    scale = min(MNIST_INNER_SIZE / digit_width, MNIST_INNER_SIZE / digit_height)
    scaled_width = max(1, round(digit_width * scale))
    scaled_height = max(1, round(digit_height * scale))

    scaled = crop.scaled(
        scaled_width,
        scaled_height,
        Qt.AspectRatioMode.KeepAspectRatio,
        Qt.TransformationMode.SmoothTransformation,
    )

    normalized = QImage(GRID_WIDTH, GRID_HEIGHT, QImage.Format.Format_RGB32)
    normalized.fill(Qt.GlobalColor.white)

    offset_x = (GRID_WIDTH - scaled.width()) // 2
    offset_y = (GRID_HEIGHT - scaled.height()) // 2

    painter = QPainter(normalized)
    painter.drawImage(offset_x, offset_y, scaled)
    painter.end()

    total_ink = 0.0
    sum_x = 0.0
    sum_y = 0.0
    for row in range(GRID_HEIGHT):
        for col in range(GRID_WIDTH):
            ink = _ink_intensity(normalized.pixelColor(col, row))
            total_ink += ink
            sum_x += col * ink
            sum_y += row * ink

    if total_ink <= 0.0:
        return None, "pre-processamento gerou frame vazio"

    center_x = sum_x / total_ink
    center_y = sum_y / total_ink
    target_x = GRID_WIDTH / 2.0
    target_y = GRID_HEIGHT / 2.0
    shift_x = round(target_x - center_x)
    shift_y = round(target_y - center_y)

    frame = QImage(GRID_WIDTH, GRID_HEIGHT, QImage.Format.Format_RGB32)
    frame.fill(Qt.GlobalColor.white)

    painter = QPainter(frame)
    painter.drawImage(shift_x, shift_y, normalized)
    painter.end()

    rows: list[str] = []
    for row in range(GRID_HEIGHT):
        bits: list[str] = []
        for col in range(GRID_WIDTH):
            ink = _ink_intensity(frame.pixelColor(col, row))
            bits.append("1" if ink >= BINARIZE_THRESHOLD else "0")
        rows.append("".join(bits))

    if active_pixel_count(rows) == 0:
        return None, "pre-processamento gerou frame vazio"

    return rows, "ok"


def matrix_to_qimage(matrix: Iterable[Any], scale: int = SNAPSHOT_SCALE) -> QImage:
    rows = matrix_to_strings(matrix)
    image = QImage(
        GRID_WIDTH * scale,
        GRID_HEIGHT * scale,
        QImage.Format.Format_RGB32,
    )
    image.fill(Qt.GlobalColor.white)

    painter = QPainter(image)
    painter.setPen(Qt.PenStyle.NoPen)
    painter.setBrush(Qt.GlobalColor.black)

    for row, text in enumerate(rows):
        for col, value in enumerate(text):
            if value == "1":
                painter.drawRect(col * scale, row * scale, scale, scale)

    painter.end()
    return image

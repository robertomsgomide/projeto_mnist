#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
mnist_gui.py

GUI PySide6 para desenhar um digito, normalizar para MNIST 28x28 e enviar o
frame compactado para a ponte ESP32-S3 via protocolo textual serial.
"""

from __future__ import annotations

import math
import sys
from datetime import datetime
from typing import Any, Iterable

import serial
from serial.tools import list_ports

from PySide6.QtCore import QEvent, QObject, QPointF, Qt, QThread, QTimer, Signal, Slot
from PySide6.QtGui import QColor, QImage, QMouseEvent, QPainter, QPaintEvent, QPen, QPixmap
from PySide6.QtWidgets import (
    QApplication,
    QCheckBox,
    QComboBox,
    QFrame,
    QGridLayout,
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QPushButton,
    QSpinBox,
    QTextEdit,
    QVBoxLayout,
    QWidget,
    QStyle,
)


CANVAS_SIZE = 560
GRID_WIDTH = 28
GRID_HEIGHT = 28
IMG_BITS = GRID_WIDTH * GRID_HEIGHT

STROKE_WIDTH = 44
MNIST_INNER_SIZE = 20
DARK_PIXEL_THRESHOLD = 220
INK_DETECT_THRESHOLD = 0.05
BINARIZE_THRESHOLD = 0.30
PRESSURE_WIDTH_MIN = 0.12
PRESSURE_WIDTH_MAX = 1.0
STROKE_INTERPOLATION_SPACING = 0.45
PREVIEW_SCALE = 9
STROKE_INTENSITY = 1.0
RELATIVE_WIDTH_ENABLED = True
RELATIVE_REFERENCE_BBOX = CANVAS_SIZE * 0.45
RELATIVE_MIN_WIDTH_SCALE = 0.35
RELATIVE_MAX_WIDTH_SCALE = 1.80

UART_PAYLOAD_BYTES = IMG_BITS // 8
DEFAULT_BAUD = 1_000_000

ZERO_MATRIX = ["0" * GRID_WIDTH for _ in range(GRID_HEIGHT)]
StrokePoint = tuple[QPointF, float]
Stroke = list[StrokePoint]
StrokeBBox = tuple[float, float, float, float]


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
            raise ValueError(f"matrix linha {index} deve ter {GRID_WIDTH} colunas")

        for value in row:
            if value not in (0, 1):
                raise ValueError("matrix deve conter somente 0/1")

    return rows


def matrix_to_strings(matrix: Iterable[Any]) -> list[str]:
    rows = _normaliza_matriz(matrix)
    return ["".join("1" if value else "0" for value in row) for row in rows]


def matrix_to_payload(matrix: Iterable[Any]) -> list[int]:
    rows = _normaliza_matriz(matrix)
    payload = [0 for _ in range(UART_PAYLOAD_BYTES)]

    for row in range(GRID_HEIGHT):
        for col in range(GRID_WIDTH):
            if rows[row][col]:
                pixel_index = row * GRID_WIDTH + col
                byte_index = pixel_index // 8
                bit_index = 7 - (pixel_index % 8)
                payload[byte_index] |= 1 << bit_index

    return payload


def payload_to_hex(payload: Iterable[int]) -> str:
    values = list(payload)
    if len(values) != UART_PAYLOAD_BYTES:
        raise ValueError(f"payload deve ter {UART_PAYLOAD_BYTES} bytes")

    for value in values:
        if not 0 <= int(value) <= 0xFF:
            raise ValueError("payload deve conter bytes entre 0 e 255")

    return "".join(f"{int(value):02X}" for value in values)


def active_pixel_count(matrix: Iterable[Any]) -> int:
    return sum(row.count("1") for row in matrix_to_strings(matrix))


def _luminance_255(color: QColor) -> float:
    return 0.299 * color.red() + 0.587 * color.green() + 0.114 * color.blue()


def _ink_intensity(color: QColor) -> float:
    luminance = _luminance_255(color) / 255.0
    return max(0.0, min(1.0, 1.0 - luminance))


def _pressure_width_factor(pressure: float) -> float:
    pressure = max(0.0, min(1.0, pressure))
    return PRESSURE_WIDTH_MIN + (PRESSURE_WIDTH_MAX - PRESSURE_WIDTH_MIN) * pressure


def _stroke_width_for_pressure(base_width: float, pressure: float) -> float:
    return max(1.0, base_width * _pressure_width_factor(pressure))


def _stroke_color() -> QColor:
    gray = round(255 * (1.0 - STROKE_INTENSITY))
    return QColor(gray, gray, gray)


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
    bbox: StrokeBBox | None,
    base_width: float = STROKE_WIDTH,
) -> float:
    if not RELATIVE_WIDTH_ENABLED or bbox is None:
        return base_width

    bbox_width, bbox_height = bbox_dimensions(bbox)
    bbox_size = max(bbox_width, bbox_height)
    scale = bbox_size / RELATIVE_REFERENCE_BBOX
    effective_width = base_width * scale
    return clamp(
        effective_width,
        base_width * RELATIVE_MIN_WIDTH_SCALE,
        base_width * RELATIVE_MAX_WIDTH_SCALE,
    )


def _draw_stroke(painter: QPainter, stroke: Stroke, base_width: float) -> None:
    if not stroke:
        return

    first_pos, first_pressure = stroke[0]
    first_width = _stroke_width_for_pressure(base_width, first_pressure)
    color = _stroke_color()
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
        avg_width = (
            _stroke_width_for_pressure(base_width, start_pressure)
            + _stroke_width_for_pressure(base_width, pressure)
        ) / 2.0
        spacing = max(1.0, avg_width * STROKE_INTERPOLATION_SPACING)
        steps = max(1, math.ceil(distance / spacing))

        previous = start
        for step in range(1, steps + 1):
            t = step / steps
            current = QPointF(start.x() + dx * t, start.y() + dy * t)
            current_pressure = start_pressure + (pressure - start_pressure) * t
            pen.setWidthF(_stroke_width_for_pressure(base_width, current_pressure))
            painter.setPen(pen)
            painter.drawLine(previous, current)
            previous = current

        start = pos
        start_pressure = pressure


def render_strokes_to_qimage(
    strokes: Iterable[Iterable[StrokePoint]],
    base_width: float = STROKE_WIDTH,
) -> QImage:
    stroke_lists = [list(stroke) for stroke in strokes]
    effective_width = effective_base_width(stroke_points_bbox(stroke_lists), base_width)

    image = QImage(CANVAS_SIZE, CANVAS_SIZE, QImage.Format.Format_RGB32)
    image.fill(Qt.GlobalColor.white)

    painter = QPainter(image)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing, True)
    for stroke in stroke_lists:
        _draw_stroke(painter, stroke, effective_width)
    painter.end()
    return image


def render_strokes_for_preprocess(strokes: Iterable[Iterable[StrokePoint]]) -> QImage:
    return render_strokes_to_qimage(strokes, STROKE_WIDTH)


def preprocess_qimage_to_matrix(image: QImage) -> tuple[list[str] | None, str]:
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


def matrix_to_qimage(matrix: Iterable[Any], scale: int = PREVIEW_SCALE) -> QImage:
    rows = matrix_to_strings(matrix)
    image = QImage(GRID_WIDTH * scale, GRID_HEIGHT * scale, QImage.Format.Format_RGB32)
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


class DrawingCanvas(QWidget):
    changed = Signal()

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setFixedSize(CANVAS_SIZE, CANVAS_SIZE)
        self.setMouseTracking(True)
        self.setAutoFillBackground(False)

        self.image = QImage(CANVAS_SIZE, CANVAS_SIZE, QImage.Format.Format_RGB32)
        self.image.fill(Qt.GlobalColor.white)

        self.drawing_enabled = False
        self.pointer_down = False
        self.last_pos: QPointF | None = None
        self.last_pressure: float | None = None
        self.strokes: list[Stroke] = []
        self.current_stroke: Stroke | None = None

    def clear(self) -> None:
        self.image.fill(Qt.GlobalColor.white)
        self.pointer_down = False
        self.last_pos = None
        self.last_pressure = None
        self.strokes = []
        self.current_stroke = None
        self.changed.emit()
        self.update()

    def render_preprocess_image(self) -> QImage:
        return render_strokes_for_preprocess(self.strokes)

    def _rerender(self) -> None:
        self.image = self.render_preprocess_image()
        self.changed.emit()
        self.update()

    def paintEvent(self, event: QPaintEvent) -> None:
        painter = QPainter(self)
        painter.drawImage(0, 0, self.image)
        painter.end()
        super().paintEvent(event)

    def mousePressEvent(self, event: QMouseEvent) -> None:
        if event.button() == Qt.MouseButton.LeftButton:
            self.pointer_down = True
            self._handle_point(event.position(), 1.0)

    def mouseMoveEvent(self, event: QMouseEvent) -> None:
        if self.pointer_down:
            self._handle_point(event.position(), 1.0)

    def mouseReleaseEvent(self, event: QMouseEvent) -> None:
        if event.button() == Qt.MouseButton.LeftButton:
            self.pointer_down = False
            self.last_pos = None
            self.last_pressure = None
            self.current_stroke = None
            event.accept()

    def tabletEvent(self, event: Any) -> None:
        event_type = event.type()
        if event_type == QEvent.Type.TabletPress:
            self.pointer_down = True
            pressure = self._clamp_pressure(float(event.pressure() or 1.0))
            self._handle_point(event.position(), pressure)
            event.accept()
            return

        if event_type == QEvent.Type.TabletMove:
            pressure = self._clamp_pressure(float(event.pressure() or 0.0))
            if not self.pointer_down and pressure <= 0.0:
                self.last_pos = None
                self.last_pressure = None
                self.current_stroke = None
                event.accept()
                return

            self.pointer_down = True
            self._handle_point(event.position(), pressure)
            event.accept()
            return

        if event_type == QEvent.Type.TabletRelease:
            self.pointer_down = False
            self.last_pos = None
            self.last_pressure = None
            self.current_stroke = None
            event.accept()
            return

        super().tabletEvent(event)

    def _clamp_pressure(self, pressure: float) -> float:
        return max(0.0, min(1.0, pressure))

    def _stroke_width(self, pressure: float) -> float:
        return _stroke_width_for_pressure(STROKE_WIDTH, pressure)

    def _handle_point(self, pos: QPointF, pressure: float) -> None:
        pressure = self._clamp_pressure(pressure)
        if not self.drawing_enabled:
            self.last_pos = None
            self.last_pressure = None
            self.current_stroke = None
            return

        if not self.rect().contains(pos.toPoint()):
            self.last_pos = None
            self.last_pressure = None
            self.current_stroke = None
            return

        if self.last_pos is None:
            self.current_stroke = [(QPointF(pos), pressure)]
            self.strokes.append(self.current_stroke)
        else:
            start = self.last_pos
            start_pressure = self.last_pressure
            if start_pressure is None:
                start_pressure = pressure
            if self.current_stroke is None:
                self.current_stroke = [(QPointF(start), start_pressure)]
                self.strokes.append(self.current_stroke)
            self.current_stroke.append((QPointF(pos), pressure))

        self.last_pos = pos
        self.last_pressure = pressure
        self._rerender()


class SerialCommandWorker(QObject):
    log_line = Signal(str)
    finished = Signal(str, object, bool)

    def __init__(self, serial_port: serial.Serial | None, command: str, kind: str) -> None:
        super().__init__()
        self.serial_port = serial_port
        self.command = command.strip()
        self.kind = kind

    @Slot()
    def run(self) -> None:
        response: str | None = None
        write_ok = False

        if self.serial_port is None or not self.serial_port.is_open:
            self.log_line.emit("erro: ESP32 nao conectada")
            self.finished.emit(self.kind, response, write_ok)
            return

        try:
            line = (self.command + "\n").encode("ascii")
            self.serial_port.write(line)
            self.serial_port.flush()
            write_ok = True
            self.log_line.emit(f"> {self.command}")
        except (OSError, serial.SerialException, UnicodeEncodeError) as exc:
            self.log_line.emit(f"erro serial ao enviar: {exc}")
            self.finished.emit(self.kind, response, write_ok)
            return

        try:
            for _ in range(20):
                raw = self.serial_port.readline()
                if not raw:
                    self.log_line.emit("erro: timeout aguardando resposta")
                    self.finished.emit(self.kind, response, write_ok)
                    return

                text = raw.decode("ascii", errors="replace").strip()
                if not text:
                    continue

                self.log_line.emit(f"< {text}")
                if text.startswith("LOG "):
                    continue

                response = text
                self.finished.emit(self.kind, response, write_ok)
                return

            self.log_line.emit("erro: muitas linhas LOG sem resposta final")
            self.finished.emit(self.kind, response, write_ok)
        except (OSError, serial.SerialException) as exc:
            self.log_line.emit(f"erro serial ao ler: {exc}")
            self.finished.emit(self.kind, response, write_ok)


class MnistHardwareGui(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("MNIST FPGA Hardware Bridge")
        self.setWindowIcon(self.style().standardIcon(QStyle.StandardPixmap.SP_DriveNetIcon))
        self.serial_port: serial.Serial | None = None
        self.serial_thread: QThread | None = None
        self.serial_worker: SerialCommandWorker | None = None
        self.pending_command_context: dict[str, Any] | None = None
        self.command_pending = False
        self.seq_next = 0
        self.last_matrix = list(ZERO_MATRIX)
        self.preview_timer = QTimer(self)
        self.preview_timer.setSingleShot(True)
        self.preview_timer.setInterval(125)
        self.preview_timer.timeout.connect(self.update_preview)

        self._build_ui()
        self.refresh_ports()
        self.update_preview()
        self.update_status()
        self.log("pronto")

    def _build_ui(self) -> None:
        central = QWidget(self)
        self.setCentralWidget(central)

        root = QHBoxLayout(central)
        root.setContentsMargins(12, 12, 12, 12)
        root.setSpacing(12)

        self.canvas = DrawingCanvas()
        self.canvas.changed.connect(self.schedule_preview_update)
        root.addWidget(self.canvas)

        side = QVBoxLayout()
        side.setSpacing(8)
        root.addLayout(side)

        serial_box = QFrame()
        serial_box.setFrameShape(QFrame.Shape.StyledPanel)
        serial_layout = QGridLayout(serial_box)

        self.port_combo = QComboBox()
        self.refresh_button = QPushButton("ATUALIZAR")
        self.baud_spin = QSpinBox()
        self.baud_spin.setRange(9600, 10_000_000)
        self.baud_spin.setValue(DEFAULT_BAUD)
        self.baud_spin.setSingleStep(115200)
        self.connect_button = QPushButton("CONECTAR")

        self.refresh_button.clicked.connect(self.refresh_ports)
        self.connect_button.clicked.connect(self.toggle_connection)

        serial_layout.addWidget(QLabel("Porta"), 0, 0)
        serial_layout.addWidget(self.port_combo, 0, 1)
        serial_layout.addWidget(self.refresh_button, 0, 2)
        serial_layout.addWidget(QLabel("Baud"), 1, 0)
        serial_layout.addWidget(self.baud_spin, 1, 1)
        serial_layout.addWidget(self.connect_button, 1, 2)
        side.addWidget(serial_box)

        controls = QGridLayout()
        self.escreve_check = QCheckBox("ESCREVE")
        self.clear_button = QPushButton("APAGAR")
        self.classify_button = QPushButton("CLASSIFICAR")
        self.ping_button = QPushButton("PING")

        self.escreve_check.toggled.connect(self.on_escreve_changed)
        self.clear_button.clicked.connect(self.on_apagar)
        self.classify_button.clicked.connect(self.on_classificar)
        self.ping_button.clicked.connect(lambda: self.start_serial_command("PING", "ping"))

        controls.addWidget(self.escreve_check, 0, 0)
        controls.addWidget(self.clear_button, 0, 1)
        controls.addWidget(self.classify_button, 1, 0)
        controls.addWidget(self.ping_button, 1, 1)
        side.addLayout(controls)

        status_box = QFrame()
        status_box.setFrameShape(QFrame.Shape.StyledPanel)
        status_layout = QGridLayout(status_box)
        self.status_labels: dict[str, QLabel] = {}
        for row, (label, key) in enumerate(
            (
                ("Serial", "serial"),
                ("SEQ", "seq"),
                ("Pixels", "pixels"),
                ("Preview", "preview_status"),
            )
        ):
            status_layout.addWidget(QLabel(label + ":"), row, 0)
            value = QLabel("--")
            value.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
            self.status_labels[key] = value
            status_layout.addWidget(value, row, 1)
        side.addWidget(status_box)

        self.preview_label = QLabel()
        self.preview_label.setFixedSize(GRID_WIDTH * PREVIEW_SCALE, GRID_HEIGHT * PREVIEW_SCALE)
        self.preview_label.setFrameShape(QFrame.Shape.StyledPanel)
        self.preview_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        side.addWidget(self.preview_label)

        self.log_edit = QTextEdit()
        self.log_edit.setReadOnly(True)
        self.log_edit.setMinimumWidth(380)
        self.log_edit.setMinimumHeight(260)
        side.addWidget(self.log_edit, 1)

    def refresh_ports(self) -> None:
        current = self.port_combo.currentData()
        self.port_combo.clear()

        ports = list(list_ports.comports())
        if not ports:
            self.port_combo.addItem("nenhuma porta serial encontrada", None)
            return

        for port in ports:
            label = f"{port.device} - {port.description}"
            self.port_combo.addItem(label, port.device)

        if current is not None:
            index = self.port_combo.findData(current)
            if index >= 0:
                self.port_combo.setCurrentIndex(index)

    def log(self, message: str) -> None:
        timestamp = datetime.now().strftime("%H:%M:%S")
        self.log_edit.append(f"[{timestamp}] {message}")

    def update_status(self) -> None:
        connected = self.serial_port is not None and self.serial_port.is_open
        port = self.serial_port.port if connected else "desconectado"
        self.status_labels["serial"].setText(str(port))
        self.status_labels["seq"].setText(f"0x{self.seq_next:02X}")
        self.status_labels["pixels"].setText(str(active_pixel_count(self.last_matrix)))

    def schedule_preview_update(self) -> None:
        self.preview_timer.start()

    def update_preview(self) -> None:
        matrix, status = preprocess_qimage_to_matrix(
            self.canvas.render_preprocess_image()
        )
        if matrix is None:
            self.last_matrix = list(ZERO_MATRIX)
            self.status_labels["preview_status"].setText(status)
            image = matrix_to_qimage(self.last_matrix)
        else:
            self.last_matrix = matrix
            self.status_labels["preview_status"].setText("ok")
            image = matrix_to_qimage(matrix)

        self.preview_label.setPixmap(QPixmap.fromImage(image))
        self.update_status()

    def toggle_connection(self) -> None:
        if self.serial_port is not None and self.serial_port.is_open:
            self.disconnect_serial()
            return

        port = self.port_combo.currentData()
        if port is None:
            self.log("erro: nenhuma porta COM selecionada")
            return

        try:
            self.serial_port = serial.Serial(
                port=str(port),
                baudrate=int(self.baud_spin.value()),
                timeout=1.5,
                write_timeout=1.0,
            )
            self.serial_port.reset_input_buffer()
            self.connect_button.setText("DESCONECTAR")
            self.port_combo.setEnabled(False)
            self.baud_spin.setEnabled(False)
            self.refresh_button.setEnabled(False)
            self.log(f"conectado em {port} @ {self.baud_spin.value()}")
            self.update_status()
        except (OSError, serial.SerialException) as exc:
            self.serial_port = None
            self.log(f"erro ao conectar: {exc}")
            self.update_status()

    def disconnect_serial(self) -> None:
        if self.serial_port is not None:
            try:
                if self.serial_port.is_open:
                    self.serial_port.close()
            except (OSError, serial.SerialException) as exc:
                self.log(f"erro ao desconectar: {exc}")

        self.serial_port = None
        self.connect_button.setText("CONECTAR")
        self.port_combo.setEnabled(True)
        self.baud_spin.setEnabled(True)
        self.refresh_button.setEnabled(True)
        self.log("desconectado")
        self.update_status()

    def _serial_ready(self) -> bool:
        return self.serial_port is not None and self.serial_port.is_open

    def set_command_controls_enabled(self, enabled: bool) -> None:
        self.ping_button.setEnabled(enabled)
        self.escreve_check.setEnabled(enabled)
        self.clear_button.setEnabled(enabled)
        self.classify_button.setEnabled(enabled)
        self.connect_button.setEnabled(enabled)

    def start_serial_command(
        self,
        command: str,
        kind: str,
        context: dict[str, Any] | None = None,
    ) -> bool:
        if self.command_pending:
            self.log("erro: comando serial em andamento")
            return False

        if not self._serial_ready():
            self.log("erro: ESP32 nao conectada")
            return False

        self.command_pending = True
        self.pending_command_context = context
        self.set_command_controls_enabled(False)

        self.serial_thread = QThread(self)
        self.serial_worker = SerialCommandWorker(self.serial_port, command, kind)
        self.serial_worker.moveToThread(self.serial_thread)

        self.serial_thread.started.connect(self.serial_worker.run)
        self.serial_worker.log_line.connect(self.log)
        self.serial_worker.finished.connect(self.on_serial_command_finished)
        self.serial_worker.finished.connect(self.serial_thread.quit)
        self.serial_worker.finished.connect(self.serial_worker.deleteLater)
        self.serial_thread.finished.connect(self.on_serial_thread_finished)
        self.serial_thread.finished.connect(self.serial_thread.deleteLater)
        self.serial_thread.start()
        return True

    @Slot(str, object, bool)
    def on_serial_command_finished(
        self,
        kind: str,
        response: object,
        write_ok: bool,
    ) -> None:
        response_text = response if isinstance(response, str) else None

        if kind == "classificar" and write_ok and response_text is not None:
            if response_text.startswith(("OK", "ERR")):
                context = self.pending_command_context or {}
                seq = int(context.get("seq", self.seq_next))
                matrix = context.get("matrix")
                self.seq_next = (seq + 1) & 0xFF
                if matrix is not None:
                    self.last_matrix = matrix
                self.update_status()

    @Slot()
    def on_serial_thread_finished(self) -> None:
        self.command_pending = False
        self.pending_command_context = None
        self.serial_thread = None
        self.serial_worker = None
        self.set_command_controls_enabled(True)
        self.update_status()

    def on_escreve_changed(self, value: bool) -> None:
        self.canvas.drawing_enabled = value
        self.start_serial_command(f"E {1 if value else 0}", "escreve")

    def on_apagar(self) -> None:
        self.canvas.clear()
        self.start_serial_command("A", "apagar")

    def on_classificar(self) -> None:
        matrix, status = preprocess_qimage_to_matrix(
            self.canvas.render_preprocess_image()
        )
        if matrix is None:
            self.log(f"CLASSIFICAR ignorado: {status}")
            return

        payload_hex = payload_to_hex(matrix_to_payload(matrix))
        seq = self.seq_next
        command = f"FC {seq:02X} {payload_hex}"

        self.start_serial_command(
            command,
            "classificar",
            {"seq": seq, "matrix": matrix},
        )

    def closeEvent(self, event: Any) -> None:
        if self.command_pending:
            self.log("aguarde o comando serial terminar antes de sair")
            event.ignore()
            return

        self.disconnect_serial()
        event.accept()


def main() -> int:
    app = QApplication(sys.argv)
    window = MnistHardwareGui()
    window.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())

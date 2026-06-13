#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
fpga_sim.py

GUI PySide6 para desenhar digitos em alta resolucao, normalizar para MNIST
28x28 e registrar sessoes consumidas por monta_tb.py.

O desenho local e apenas feedback visual. A UART recebe somente frames
completos substitutivos no clique CLASSIFICAR, quando ESCREVE esta ligado.
"""

from __future__ import annotations

import json
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable
import shutil

from PySide6.QtCore import QEvent, QPointF, Qt, Signal
from PySide6.QtGui import QImage, QMouseEvent, QPainter, QPaintEvent
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
    QTextEdit,
    QVBoxLayout,
    QWidget,
    QStyle,
)

from gui_layout import (
    BINARIZE_THRESHOLD,
    CANVAS_SIZE,
    DARK_PIXEL_THRESHOLD,
    GRID_HEIGHT,
    GRID_WIDTH,
    IMG_BITS,
    INK_DETECT_THRESHOLD,
    MNIST_INNER_SIZE,
    NORMALIZE_MARGIN,
    PRESSURE_WIDTH_MAX,
    PRESSURE_WIDTH_MIN,
    RELATIVE_MAX_WIDTH_SCALE,
    RELATIVE_MIN_WIDTH_SCALE,
    RELATIVE_REFERENCE_BBOX,
    RELATIVE_WIDTH_ENABLED,
    SNAPSHOT_SCALE,
    STROKE_INTERPOLATION_SPACING,
    STROKE_INTENSITY,
    STROKE_WIDTH,
    Stroke,
    StrokeBBox,
    StrokePoint,
    ZERO_MATRIX,
    active_pixel_count,
    default_stroke_width_for_pressure,
    image_is_dark,
    matrix_to_qimage,
    matrix_to_strings,
    preprocess_qimage_to_matrix,
    render_strokes_for_preprocess,
    render_strokes_to_qimage,
)


SCHEMA_VERSION = 1

UART_HEADER0 = 0xA5
UART_HEADER1 = 0x5A
UART_CMD_FRAME = 0x01
UART_LEN_L = 0x62
UART_LEN_H = 0x00
UART_PAYLOAD_BYTES = IMG_BITS // 8
UART_BAUD = 1_000_000

SCRIPT_DIR = Path(__file__).resolve().parent
SIM_LOGS_DIR = SCRIPT_DIR / "sim_logs"


def matrix_to_payload(matrix: Iterable[Any]) -> list[int]:
    rows = matrix_to_strings(matrix)
    payload = [0 for _ in range(UART_PAYLOAD_BYTES)]

    for row in range(GRID_HEIGHT):
        for col in range(GRID_WIDTH):
            if rows[row][col] == "1":
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


def compute_checksum(seq: int, payload: Iterable[int]) -> int:
    values = list(payload)
    if len(values) != UART_PAYLOAD_BYTES:
        raise ValueError(f"payload deve ter {UART_PAYLOAD_BYTES} bytes")

    checksum = UART_CMD_FRAME ^ UART_LEN_L ^ UART_LEN_H ^ (int(seq) & 0xFF)
    for value in values:
        if not 0 <= int(value) <= 0xFF:
            raise ValueError("payload deve conter bytes entre 0 e 255")
        checksum ^= int(value)

    return checksum & 0xFF


def make_uart_frame_packet(seq: int, matrix: Iterable[Any]) -> dict[str, Any]:
    rows = matrix_to_strings(matrix)
    payload = matrix_to_payload(rows)
    return {
        "type": "uart_frame_packet",
        "seq": int(seq) & 0xFF,
        "cmd": f"{UART_CMD_FRAME:02X}",
        "cmd_name": "UART_CMD_FRAME_C",
        "payload_hex": payload_to_hex(payload),
        "checksum": f"{compute_checksum(seq, payload):02X}",
        "matrix": rows,
        "active_pixels": active_pixel_count(rows),
    }


class DrawingCanvas(QWidget):
    changed = Signal()
    ignored = Signal(str)

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setFixedSize(CANVAS_SIZE, CANVAS_SIZE)
        self.setMouseTracking(True)
        self.setAutoFillBackground(False)

        self.image = QImage(
            CANVAS_SIZE,
            CANVAS_SIZE,
            QImage.Format.Format_RGB32,
        )
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
        return default_stroke_width_for_pressure(pressure)

    def _handle_point(self, pos: QPointF, pressure: float) -> None:
        pressure = self._clamp_pressure(pressure)
        if not self.drawing_enabled:
            self.last_pos = None
            self.last_pressure = None
            self.current_stroke = None
            self.ignored.emit("desenho ignorado: ESCREVE esta desligado")
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


class FpgaSimApp(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("MNIST FPGA UART Simulator")
        self.setWindowIcon(self.style().standardIcon(QStyle.StandardPixmap.SP_ComputerIcon))
        self.session_running = False
        self.session_dir: Path | None = None
        self.snapshot_dir: Path | None = None
        self.json_path: Path | None = None
        self.created_at = ""
        self.start_counter = 0.0

        self.events: list[dict[str, Any]] = []
        self.snapshots: list[dict[str, Any]] = []
        self.seq_next = 0
        self.last_seq: int | None = None
        self.packet_count = 0
        self.snapshot_count = 0
        self.last_snapshot_path = ""
        self.loaded_fpga_matrix = list(ZERO_MATRIX)

        self._build_ui()
        self.update_status()
        self.log_status("pronto")

    def _build_ui(self) -> None:
        central = QWidget(self)
        self.setCentralWidget(central)

        root = QHBoxLayout(central)
        root.setContentsMargins(12, 12, 12, 12)
        root.setSpacing(12)

        self.canvas = DrawingCanvas()
        self.canvas.changed.connect(self.update_status)
        self.canvas.ignored.connect(self.log_status)
        root.addWidget(self.canvas)

        side = QVBoxLayout()
        side.setSpacing(8)
        root.addLayout(side)

        self.start_button = QPushButton("INICIAR")
        self.end_button = QPushButton("ENCERRAR")
        self.clear_button = QPushButton("LIMPAR")
        self.classify_button = QPushButton("CLASSIFICAR")
        self.escreve_check = QCheckBox("ESCREVE")

        self.start_button.clicked.connect(self.start_session)
        self.end_button.clicked.connect(self.end_session)
        self.clear_button.clicked.connect(self.on_limpar)
        self.classify_button.clicked.connect(self.on_classificar)
        self.escreve_check.toggled.connect(self.on_escreve_changed)

        for button in (
            self.start_button,
            self.end_button,
            self.clear_button,
            self.classify_button,
        ):
            button.setMinimumWidth(180)
            side.addWidget(button)

        side.addWidget(self.escreve_check)

        status_box = QFrame()
        status_box.setFrameShape(QFrame.Shape.StyledPanel)
        status_layout = QGridLayout(status_box)
        self.status_labels: dict[str, QLabel] = {}
        for row, (label, key) in enumerate(
            (
                ("Sessao", "state"),
                ("ESCREVE", "escreve"),
                ("Pacotes UART", "packets"),
                ("Ultimo SEQ", "last_seq"),
                ("Ultimo snapshot", "snapshot"),
                ("JSON", "json_path"),
            )
        ):
            status_layout.addWidget(QLabel(label + ":"), row, 0)
            value = QLabel("--")
            value.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
            value.setWordWrap(True)
            self.status_labels[key] = value
            status_layout.addWidget(value, row, 1)

        side.addWidget(status_box)

        self.log_edit = QTextEdit()
        self.log_edit.setReadOnly(True)
        self.log_edit.setMinimumWidth(360)
        self.log_edit.setMinimumHeight(300)
        side.addWidget(self.log_edit, 1)

    def _relative_ms(self) -> int:
        if not self.session_running:
            return 0
        return int((time.perf_counter() - self.start_counter) * 1000)

    def update_status(self) -> None:
        state = "iniciada" if self.session_running else "parada"
        escreve = "1" if self.escreve_check.isChecked() else "0"
        last_seq = "--" if self.last_seq is None else f"0x{self.last_seq:02X}"
        snapshot = self.last_snapshot_path or "--"
        json_path = str(self.json_path) if self.json_path else "--"

        self.status_labels["state"].setText(state)
        self.status_labels["escreve"].setText(escreve)
        self.status_labels["packets"].setText(str(self.packet_count))
        self.status_labels["last_seq"].setText(last_seq)
        self.status_labels["snapshot"].setText(snapshot)
        self.status_labels["json_path"].setText(json_path)

    def log_status(self, message: str) -> None:
        timestamp = datetime.now().strftime("%H:%M:%S")
        self.log_edit.append(f"[{timestamp}] {message}")

    def log_event(self, event: dict[str, Any]) -> None:
        if "timestamp_ms" not in event:
            event["timestamp_ms"] = self._relative_ms()
        self.events.append(event)

    def start_session(self) -> None:
        if self.session_running:
            self.log_status("sessao ja esta iniciada")
            return

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.created_at = datetime.now().isoformat(timespec="seconds")
        self.session_dir = SIM_LOGS_DIR / f"session_{timestamp}"
        self.snapshot_dir = self.session_dir / "snapshots"
        self.json_path = self.session_dir / "session.json"
        self.snapshot_dir.mkdir(parents=True, exist_ok=True)

        self.canvas.clear()
        self.events = []
        self.snapshots = []
        self.seq_next = 0
        self.last_seq = None
        self.packet_count = 0
        self.snapshot_count = 0
        self.last_snapshot_path = ""
        self.loaded_fpga_matrix = list(ZERO_MATRIX)
        self.start_counter = time.perf_counter()
        self.session_running = True

        self.log_event(
            {
                "type": "controle",
                "timestamp_ms": 0,
                "name": "escreve",
                "value": 1 if self.escreve_check.isChecked() else 0,
            }
        )

        self.log_status(f"sessao iniciada: {self.session_dir}")
        self.update_status()

    def end_session(self) -> None:
        if not self.session_running:
            self.log_status("nenhuma sessao em andamento")
            self.update_status()
            return

        if self.json_path is None:
            raise RuntimeError("sessao sem caminho JSON")

        data = {
            "schema_version": SCHEMA_VERSION,
            "created_at": self.created_at,
            "ended_at": datetime.now().isoformat(timespec="seconds"),
            "canvas_size": CANVAS_SIZE,
            "grid_width": GRID_WIDTH,
            "grid_height": GRID_HEIGHT,
            "uart": {
                "header0": f"{UART_HEADER0:02X}",
                "header1": f"{UART_HEADER1:02X}",
                "cmd_frame": f"{UART_CMD_FRAME:02X}",
                "cmd_name": "UART_CMD_FRAME_C",
                "payload_bytes": UART_PAYLOAD_BYTES,
                "len_l": f"{UART_LEN_L:02X}",
                "len_h": f"{UART_LEN_H:02X}",
                "baud": UART_BAUD,
            },
            "preprocess": {
                "stroke_width": STROKE_WIDTH,
                "component_policy": "all_ink_pixels",
                "pressure_width_min": PRESSURE_WIDTH_MIN,
                "pressure_width_max": PRESSURE_WIDTH_MAX,
                "stroke_interpolation_spacing": STROKE_INTERPOLATION_SPACING,
                "normalization_margin": NORMALIZE_MARGIN,
                "mnist_inner_size": MNIST_INNER_SIZE,
                "ink_detect_threshold": INK_DETECT_THRESHOLD,
                "binarize_threshold": BINARIZE_THRESHOLD,
            },
            "events": self.events,
            "snapshots": self.snapshots,
            "final_matrix": list(self.loaded_fpga_matrix),
        }

        with self.json_path.open("w", encoding="utf-8") as fp:
            json.dump(data, fp, ensure_ascii=False, indent=2)
            fp.write("\n")

        self.session_running = False
        self.log_status(f"sessao salva: {self.json_path}")
        self.update_status()
        QMessageBox.information(self, "Sessao salva", f"JSON salvo em:\n{self.json_path}")
        print(
            "Next: python python/monta_tb.py "
            f"python/sim_logs/{self.session_dir.name}/session.json "
            "--out VHDL/testbenches/tb_mnist_top.vhd"
        )

    def on_escreve_changed(self, value: bool) -> None:
        self.canvas.drawing_enabled = value
        if self.session_running:
            self.log_event(
                {
                    "type": "controle",
                    "name": "escreve",
                    "value": 1 if value else 0,
                }
            )
        self.log_status(f"ESCREVE={'1' if value else '0'}")
        self.update_status()

    def on_limpar(self) -> None:
        self.canvas.clear()
        self.loaded_fpga_matrix = list(ZERO_MATRIX)

        if self.session_running:
            payload = matrix_to_payload(self.loaded_fpga_matrix)
            self.log_event(
                {
                    "type": "controle_pulso",
                    "name": "apaga",
                    "matrix": list(self.loaded_fpga_matrix),
                    "payload_hex": payload_to_hex(payload),
                    "active_pixels": 0,
                }
            )

        self.log_status("canvas limpo; modelo FPGA zerado")
        self.update_status()

    def on_classificar(self) -> None:
        if not self.session_running:
            self.log_status("CLASSIFICAR ignorado: inicie uma sessao")
            return

        if not self.escreve_check.isChecked():
            self.log_status("CLASSIFICAR ignorado: ESCREVE esta desligado")
            return

        matrix, status = preprocess_qimage_to_matrix(
            self.canvas.render_preprocess_image()
        )
        if matrix is None:
            self.log_status(f"CLASSIFICAR ignorado: {status}")
            return

        packet = make_uart_frame_packet(self.seq_next, matrix)
        packet["timestamp_ms"] = self._relative_ms()
        self.log_event(packet)

        self.loaded_fpga_matrix = list(matrix)
        self.last_seq = self.seq_next
        self.seq_next = (self.seq_next + 1) & 0xFF
        self.packet_count += 1

        snapshot = self.save_snapshot(matrix, self.last_seq)
        self.log_event(
            {
                "type": "controle_pulso",
                "name": "classifica",
                "seq": self.last_seq,
                "snapshot_index": snapshot["snapshot_index"],
            }
        )

        self.log_status(
            "frame enviado e classificacao solicitada "
            f"(seq=0x{self.last_seq:02X}, pixels={packet['active_pixels']})"
        )
        self.update_status()

    def save_snapshot(self, matrix: Iterable[Any], seq: int | None) -> dict[str, Any]:
        if not self.session_running or self.snapshot_dir is None:
            raise RuntimeError("inicie uma sessao antes de salvar snapshot")

        snapshot_index = self.snapshot_count
        path = self.snapshot_dir / f"snapshot_{snapshot_index:04d}.png"
        matrix_rows = matrix_to_strings(matrix)
        matrix_to_qimage(matrix_rows).save(str(path))

        repo_root = Path(__file__).resolve().parent.parent
        rel_path = "../" + path.resolve().relative_to(repo_root).as_posix()

        payload = matrix_to_payload(matrix_rows)
        snapshot = {
            "type": "snapshot",
            "timestamp_ms": self._relative_ms(),
            "snapshot_index": snapshot_index,
            "path": str(rel_path),
            "matrix": matrix_rows,
            "payload_hex": payload_to_hex(payload),
            "seq": 0 if seq is None else seq,
            "active_pixels": active_pixel_count(matrix_rows),
        }

        self.snapshots.append(snapshot)
        self.log_event(dict(snapshot))

        self.snapshot_count += 1
        self.last_snapshot_path = str(path)
        return snapshot

    def discard_session(self) -> None:
        """Encerra a sessao jogando fora tudo que foi gravado em disco."""
        if not self.session_running:
            return
        self.session_running = False
        if self.session_dir is not None and self.session_dir.exists():
            try:
                shutil.rmtree(self.session_dir)
                self.log_status(f"sessao descartada: {self.session_dir}")
            except OSError as exc:
                self.log_status(f"falha ao descartar sessao: {exc}")
        self.update_status()

    def closeEvent(self, event: Any) -> None:
        if not self.session_running:
            event.accept()
            return

        choice = QMessageBox.question(
            self,
            "Sessao aberta",
            "Ha uma sessao em andamento. Deseja salvar antes de sair?",
            QMessageBox.StandardButton.Save
            | QMessageBox.StandardButton.Discard
            | QMessageBox.StandardButton.Cancel,
            QMessageBox.StandardButton.Cancel,
        )

        if choice == QMessageBox.StandardButton.Cancel:
            event.ignore()
            return

        if choice == QMessageBox.StandardButton.Save:
            try:
                self.end_session()
            except Exception as exc:
                QMessageBox.critical(self, "Erro ao salvar", str(exc))
                event.ignore()
                return
        else:  # Discard -> apaga a pasta da sessao
            self.discard_session()

        event.accept()  # Save (ok) ou Discard -> fecha

_APP: FpgaSimApp | None = None


def _require_app() -> FpgaSimApp:
    if _APP is None:
        raise RuntimeError("aplicacao PySide6 ainda nao foi inicializada")
    return _APP


def save_snapshot() -> dict[str, Any]:
    app = _require_app()
    return app.save_snapshot(app.loaded_fpga_matrix, app.last_seq)


def log_event(event: dict[str, Any]) -> None:
    _require_app().log_event(event)


def start_session() -> None:
    _require_app().start_session()


def end_session() -> None:
    _require_app().end_session()


def main() -> int:
    app = QApplication(sys.argv)
    global _APP
    _APP = FpgaSimApp()
    _APP.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())

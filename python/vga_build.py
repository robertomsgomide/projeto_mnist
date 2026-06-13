#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
vga_build.py

Reconstrui snapshots PNG a partir do vga_log.txt gerado pelo testbench VGA.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover - mensagem tratada no main
    Image = None  # type: ignore[assignment]


VGA_WIDTH = 640
VGA_HEIGHT = 480

BEGIN_RE = re.compile(
    r"^BEGIN_SNAPSHOT\s+kind=([A-Za-z0-9_-]+)\s+"
    r"event=([0-9]{4})\s+width=([0-9]+)\s+height=([0-9]+)$"
)
ROW_RE = re.compile(r"^ROW\s+([0-9]{3})\s+(.+)$")
PIXEL_RE = re.compile(r"^[0-9A-Fa-f]{3}$")


class VgaLogError(Exception):
    """Erro de formato no log VGA."""


@dataclass
class Snapshot:
    kind: str
    event: str
    width: int
    height: int
    start_line: int
    rows: list[list[str]]


def resolve_log_path(path: Path) -> tuple[Path, Path]:
    if path.is_dir():
        return path / "vga_log.txt", path
    return path, path.parent


def parse_begin(line: str, line_number: int) -> Snapshot:
    match = BEGIN_RE.fullmatch(line)
    if match is None:
        raise VgaLogError(f"linha {line_number}: BEGIN_SNAPSHOT invalido")

    kind, event, width_text, height_text = match.groups()
    width = int(width_text)
    height = int(height_text)

    if width != VGA_WIDTH or height != VGA_HEIGHT:
        raise VgaLogError(
            f"linha {line_number}: dimensoes {width}x{height}; "
            f"esperado {VGA_WIDTH}x{VGA_HEIGHT}"
        )

    return Snapshot(
        kind=kind,
        event=event,
        width=width,
        height=height,
        start_line=line_number,
        rows=[],
    )


def parse_row(line: str, line_number: int, snapshot: Snapshot) -> None:
    match = ROW_RE.fullmatch(line)
    if match is None:
        raise VgaLogError(f"linha {line_number}: ROW invalido")

    row_index = int(match.group(1))
    expected_row = len(snapshot.rows)
    if row_index != expected_row:
        raise VgaLogError(
            f"linha {line_number}: ROW {row_index:03d}; "
            f"esperado ROW {expected_row:03d}"
        )

    pixels = match.group(2).split()
    if len(pixels) != snapshot.width:
        raise VgaLogError(
            f"linha {line_number}: ROW {row_index:03d} tem {len(pixels)} pixels; "
            f"esperado {snapshot.width}"
        )

    for col, pixel in enumerate(pixels):
        if PIXEL_RE.fullmatch(pixel) is None:
            raise VgaLogError(
                f"linha {line_number}: pixel invalido em coluna {col}: {pixel!r}"
            )

    snapshot.rows.append([pixel.upper() for pixel in pixels])


def parse_vga_log(log_path: Path) -> list[Snapshot]:
    snapshots: list[Snapshot] = []
    current: Snapshot | None = None

    with log_path.open("r", encoding="utf-8") as fp:
        for line_number, raw_line in enumerate(fp, start=1):
            line = raw_line.rstrip("\r\n")

            if line.strip() == "":
                if current is None:
                    continue
                raise VgaLogError(
                    f"linha {line_number}: linha vazia dentro de snapshot"
                )

            if line.startswith("BEGIN_SNAPSHOT"):
                if current is not None:
                    raise VgaLogError(
                        f"linha {line_number}: novo snapshot antes de END_SNAPSHOT"
                    )
                current = parse_begin(line, line_number)
                continue

            if line.startswith("ROW"):
                if current is None:
                    raise VgaLogError(f"linha {line_number}: ROW fora de snapshot")
                parse_row(line, line_number, current)
                continue

            if line == "END_SNAPSHOT":
                if current is None:
                    raise VgaLogError(
                        f"linha {line_number}: END_SNAPSHOT fora de snapshot"
                    )
                if len(current.rows) != current.height:
                    raise VgaLogError(
                        f"linha {line_number}: snapshot iniciado na linha "
                        f"{current.start_line} tem {len(current.rows)} linhas; "
                        f"esperado {current.height}"
                    )
                snapshots.append(current)
                current = None
                continue

            raise VgaLogError(f"linha {line_number}: conteudo inesperado: {line!r}")

    if current is not None:
        raise VgaLogError(
            f"snapshot iniciado na linha {current.start_line} nao terminou"
        )

    if not snapshots:
        raise VgaLogError("nenhum snapshot encontrado no log")

    return snapshots


def rgb444_to_rgb888(pixel: str) -> tuple[int, int, int]:
    return (
        int(pixel[0], 16) * 17,
        int(pixel[1], 16) * 17,
        int(pixel[2], 16) * 17,
    )


def snapshot_filename(snapshot: Snapshot) -> str:
    safe_kind = re.sub(r"[^A-Za-z0-9_-]+", "_", snapshot.kind).lower()
    return f"vga_{safe_kind}_evt{snapshot.event}.png"


def write_snapshot_png(snapshot: Snapshot, out_dir: Path) -> Path:
    if Image is None:
        raise VgaLogError("Pillow nao esta instalado; execute: pip install Pillow")

    pixels = [
        rgb444_to_rgb888(pixel)
        for row in snapshot.rows
        for pixel in row
    ]

    image = Image.new("RGB", (snapshot.width, snapshot.height))
    image.putdata(pixels)

    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / snapshot_filename(snapshot)
    image.save(out_path)
    return out_path


def build_snapshots(input_path: Path) -> list[Path]:
    log_path, session_dir = resolve_log_path(input_path)
    if not log_path.exists():
        raise VgaLogError(f"log VGA nao encontrado: {log_path}")
    if not log_path.is_file():
        raise VgaLogError(f"caminho nao e arquivo: {log_path}")

    snapshots = parse_vga_log(log_path)
    out_dir = session_dir / "vga_snapshots"
    return [write_snapshot_png(snapshot, out_dir) for snapshot in snapshots]


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Converte vga_log.txt em snapshots PNG da GUI VGA."
    )
    parser.add_argument(
        "path",
        help="diretorio da sessao ou caminho direto para vga_log.txt",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)

    try:
        generated_paths = build_snapshots(Path(args.path))
    except VgaLogError as exc:
        print(f"Erro: {exc}", file=sys.stderr)
        return 1
    except OSError as exc:
        print(f"Erro de arquivo: {exc}", file=sys.stderr)
        return 1

    for path in generated_paths:
        print(f"PNG gerado: {path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

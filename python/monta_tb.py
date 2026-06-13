#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
monta_tb.py

Le uma sessao JSON gerada por fpga_sim.py e gera um testbench VHDL-2008
estrutural e observacional para a integracao MNIST/UART.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1

GRID_WIDTH = 28
GRID_HEIGHT = 28
IMG_BITS = GRID_WIDTH * GRID_HEIGHT

UART_CMD_FRAME = 0x01
UART_LEN_L = 0x62
UART_LEN_H = 0x00
UART_PAYLOAD_BYTES = IMG_BITS // 8

EVENT_CONTROLE = "controle"
EVENT_CONTROLE_PULSO = "controle_pulso"
EVENT_UART_FRAME = "uart_frame_packet"
EVENT_UART_IMAGE_LEGACY = "uart_image_packet"
EVENT_SNAPSHOT = "snapshot"

KNOWN_EVENTS = {
    EVENT_CONTROLE,
    EVENT_CONTROLE_PULSO,
    EVENT_UART_FRAME,
    EVENT_UART_IMAGE_LEGACY,
    EVENT_SNAPSHOT,
}

PROJECT_ROOT = Path(__file__).resolve().parents[1]


class SessionError(Exception):
    """Erro de validacao da sessao."""


def fail(message: str) -> None:
    raise SessionError(message)


def display_path(value: Any) -> str:
    if value is None or value == "":
        return ""

    text = str(value)
    path = Path(text)

    if not path.is_absolute():
        return path.as_posix()

    try:
        return path.resolve(strict=False).relative_to(PROJECT_ROOT).as_posix()
    except ValueError:
        return text


def normaliza_matriz(matrix: Any, context: str) -> list[str]:
    if not isinstance(matrix, list):
        fail(f"{context}: matrix deve ser lista de {GRID_HEIGHT} linhas")

    rows: list[str] = []
    for row_index, row in enumerate(matrix):
        if isinstance(row, str):
            text = row.strip()
        elif isinstance(row, list):
            try:
                text = "".join("1" if int(value) else "0" for value in row)
            except Exception as exc:
                fail(f"{context}: matrix linha {row_index} contem valor invalido")
                raise AssertionError from exc
        else:
            fail(f"{context}: matrix linha {row_index} deve ser string ou lista")

        if len(text) != GRID_WIDTH:
            fail(f"{context}: matrix linha {row_index} deve ter {GRID_WIDTH} bits")
        if any(ch not in "01" for ch in text):
            fail(f"{context}: matrix linha {row_index} deve conter somente 0/1")

        rows.append(text)

    if len(rows) != GRID_HEIGHT:
        fail(f"{context}: matrix deve ter {GRID_HEIGHT} linhas")

    return rows


def matrix_to_payload(matrix: list[str]) -> list[int]:
    payload = [0 for _ in range(UART_PAYLOAD_BYTES)]

    for row in range(GRID_HEIGHT):
        for col in range(GRID_WIDTH):
            if matrix[row][col] == "1":
                pixel_index = row * GRID_WIDTH + col
                byte_index = pixel_index // 8
                bit_index = 7 - (pixel_index % 8)
                payload[byte_index] |= 1 << bit_index

    return payload


def payload_to_hex(payload: list[int]) -> str:
    return "".join(f"{value:02X}" for value in payload)


def payload_from_hex(value: Any, context: str) -> list[int]:
    if not isinstance(value, str):
        fail(f"{context}: payload_hex deve ser string hexadecimal")

    text = re.sub(r"\s+", "", value).upper()
    if text.startswith("0X"):
        text = text[2:]

    expected_chars = UART_PAYLOAD_BYTES * 2
    if len(text) != expected_chars:
        fail(
            f"{context}: payload_hex deve ter {expected_chars} caracteres "
            f"({UART_PAYLOAD_BYTES} bytes)"
        )
    if not re.fullmatch(r"[0-9A-F]+", text):
        fail(f"{context}: payload_hex contem caractere nao hexadecimal")

    return [int(text[i : i + 2], 16) for i in range(0, len(text), 2)]


def compute_checksum(seq: int, payload: list[int]) -> int:
    if len(payload) != UART_PAYLOAD_BYTES:
        fail(f"payload deve ter {UART_PAYLOAD_BYTES} bytes")

    checksum = UART_CMD_FRAME ^ UART_LEN_L ^ UART_LEN_H ^ (seq & 0xFF)
    for value in payload:
        if not 0 <= value <= 0xFF:
            fail("payload contem byte fora da faixa 0..255")
        checksum ^= value

    return checksum & 0xFF


def is_uart_frame_event(event: dict[str, Any]) -> bool:
    return event.get("type") in (EVENT_UART_FRAME, EVENT_UART_IMAGE_LEGACY)


def parse_byte(value: Any, context: str) -> int:
    if isinstance(value, bool):
        fail(f"{context}: valor booleano nao e byte valido")

    if isinstance(value, int):
        parsed = value
    elif isinstance(value, str):
        text = value.strip()
        if text.lower().startswith("0x"):
            text = text[2:]
        try:
            parsed = int(text, 16)
        except ValueError as exc:
            fail(f"{context}: valor hexadecimal invalido")
            raise AssertionError from exc
    else:
        fail(f"{context}: valor deve ser inteiro ou string hexadecimal")

    if not 0 <= parsed <= 0xFF:
        fail(f"{context}: valor deve estar entre 0 e 255")

    return parsed


def parse_logic_value(value: Any, context: str) -> int:
    if isinstance(value, bool):
        return 1 if value else 0
    if isinstance(value, int) and value in (0, 1):
        return value
    fail(f"{context}: value deve ser 0/1 ou booleano")
    return 0


def parse_control_name(event: dict[str, Any], context: str) -> str:
    name = event.get("name", event.get("sinal"))
    if not isinstance(name, str):
        fail(f"{context}: controle deve informar name ou sinal")

    name = name.strip().lower()
    if name not in ("escreve", "apaga", "classifica"):
        fail(f"{context}: controle invalido {name!r}")

    return name


def validate_matrix_matches_payload(
    event: dict[str, Any],
    payload: list[int],
    context: str,
) -> list[str] | None:
    if "matrix" not in event:
        return None

    matrix = normaliza_matriz(event["matrix"], context)
    expected_payload = matrix_to_payload(matrix)
    if expected_payload != payload:
        fail(f"{context}: matrix nao corresponde ao payload_hex")

    return matrix


def validate_session(data: Any, source_path: Path) -> list[dict[str, Any]]:
    if not isinstance(data, dict):
        fail("session.json deve conter um objeto JSON no topo")

    if data.get("schema_version") != SCHEMA_VERSION:
        fail(
            "schema_version incompativel: "
            f"esperado {SCHEMA_VERSION}, recebido {data.get('schema_version')!r}"
        )

    events = data.get("events")
    if not isinstance(events, list):
        fail("session.json deve conter lista 'events'")

    normalized: list[dict[str, Any]] = []
    seen_snapshot_indices: set[int] = set()

    for index, raw_event in enumerate(events):
        context = f"evento {index}"
        if not isinstance(raw_event, dict):
            fail(f"{context}: evento deve ser objeto JSON")

        event_type = raw_event.get("type")
        if event_type not in KNOWN_EVENTS:
            fail(f"{context}: evento desconhecido {event_type!r}")

        event = dict(raw_event)
        event["_event_index"] = index

        if event_type == EVENT_CONTROLE:
            name = parse_control_name(event, context)
            if name != "escreve":
                fail(f"{context}: controle de nivel suporta somente escreve")
            event["_name"] = name
            event["_value"] = parse_logic_value(event.get("value"), context)

        elif event_type in (EVENT_UART_FRAME, EVENT_UART_IMAGE_LEGACY):
            seq = parse_byte(event.get("seq"), f"{context} seq")
            if "cmd" in event:
                cmd = parse_byte(event.get("cmd"), f"{context} cmd")
                if cmd != UART_CMD_FRAME:
                    fail(
                        f"{context}: cmd 0x{cmd:02X} nao corresponde a "
                        f"UART_CMD_FRAME 0x{UART_CMD_FRAME:02X}"
                    )
            payload = payload_from_hex(event.get("payload_hex"), context)
            checksum = parse_byte(event.get("checksum"), f"{context} checksum")
            expected_checksum = compute_checksum(seq, payload)
            if checksum != expected_checksum:
                fail(
                    f"{context}: checksum registrado 0x{checksum:02X} nao bate "
                    f"com recalculado 0x{expected_checksum:02X}"
                )

            event["_seq"] = seq
            event["_payload"] = payload
            event["_matrix"] = validate_matrix_matches_payload(event, payload, context)
            event["_payload_const"] = f"FRAME_EVT_{index:04d}_PAYLOAD_C"

        elif event_type == EVENT_CONTROLE_PULSO:
            name = parse_control_name(event, context)
            if name not in ("apaga", "classifica"):
                fail(f"{context}: controle_pulso deve usar apaga ou classifica")
            event["_name"] = name

            if name == "apaga" and "payload_hex" in event:
                payload = payload_from_hex(event["payload_hex"], context)
                event["_payload"] = payload
                event["_matrix"] = validate_matrix_matches_payload(
                    event,
                    payload,
                    context,
                )

        elif event_type == EVENT_SNAPSHOT:
            snapshot_index = event.get("snapshot_index")
            if not isinstance(snapshot_index, int) or snapshot_index < 0:
                fail(f"{context}: snapshot_index deve ser inteiro >= 0")
            if snapshot_index in seen_snapshot_indices:
                fail(f"{context}: snapshot_index duplicado {snapshot_index}")
            seen_snapshot_indices.add(snapshot_index)

            payload = payload_from_hex(event.get("payload_hex"), context)
            event["_seq"] = parse_byte(event.get("seq", 0), f"{context} seq")
            event["_payload"] = payload
            event["_matrix"] = validate_matrix_matches_payload(event, payload, context)
            event["_payload_const"] = f"SNAPSHOT_{snapshot_index:04d}_PAYLOAD_C"
            event["_image_const"] = f"SNAPSHOT_{snapshot_index:04d}_IMAGE_C"

        normalized.append(event)

    final_matrix = data.get("final_matrix")
    if final_matrix is not None:
        matrix = normaliza_matriz(final_matrix, "final_matrix")
        data["_final_payload"] = matrix_to_payload(matrix)

    if not source_path.exists():
        fail(f"arquivo JSON nao existe: {source_path}")

    return normalized


def vhdl_string(value: Any) -> str:
    return str(value).replace('"', '""')


def vhdl_path(value: Path) -> str:
    return str(value).replace("\\", "/")


def vga_log_path(session_path: Path) -> Path:
    return session_path.parent / "vga_log.txt"


def vhdl_payload_constant(name: str, payload: list[int]) -> list[str]:
    lines = [f"    constant {name} : uart_frame_payload_t := ("]

    for start in range(0, len(payload), 6):
        end = min(start + 6, len(payload))
        parts = [f'{i} => x"{payload[i]:02X}"' for i in range(start, end)]
        suffix = "," if end < len(payload) else ""
        lines.append("        " + ", ".join(parts) + suffix)

    lines.append("    );")
    return lines


def emit_architecture_header(
    lines: list[str],
    session_path: Path,
    generated_at: str,
    verbose: bool,
    with_vga: bool,
) -> None:
    verbose_literal = "true" if verbose else "false"

    lines.extend(
        [
            "-------------------------------------------------------------------------------",
            "-- Arquivo gerado automaticamente por python/monta_tb.py",
            f"-- Sessao : {display_path(session_path)}",
            f"-- Gerado : {generated_at}",
            "--",
            "-- Replay por UART e controles logicos sincronizados.",
        ]
    )

    context_lines = [
        "-------------------------------------------------------------------------------",
        "library ieee;",
        "use ieee.std_logic_1164.all;",
        "use ieee.numeric_std.all;",
        "use std.env.all;",
    ]
    if with_vga:
        context_lines.append("use std.textio.all;")
    context_lines.extend(
        [
            "use work.mnist_tipos_pkg.all;",
            "use work.tb_uart_mnist_pkg.all;",
            "",
            "entity tb_mnist_top is",
            "end entity tb_mnist_top;",
            "",
            "architecture sim of tb_mnist_top is",
            "",
        ]
    )
    lines.extend(context_lines)

    lines.extend(
        [
            "    constant TB_CONTROL_SYNC_WAIT_C : natural := 4;",
            "    constant TB_RESULT_TIMEOUT_C : natural := 10000;",
            "    constant TB_POST_PACKET_WAIT_C : natural := 20;",
            "    constant TB_REPORT_CANVAS_DIFFS_C : boolean := true;",
            f"    constant TB_VERBOSE_C : boolean := {verbose_literal};",
            "",
            "    signal clock_50 : std_logic := '0';",
            "",
            "    signal escreve    : std_logic := '0';",
            "    signal apaga      : std_logic := '0';",
            "    signal classifica : std_logic := '0';",
            "",
            "    signal uart_rx_serial : std_logic := '1';",
            "    signal uart_tx_serial : std_logic;",
            "",
            "    signal ledr : led_bus_t;",
            "    signal hex0 : hex7seg_t;",
            "    signal hex1 : hex7seg_t;",
            "    signal hex2 : hex7seg_t;",
            "    signal hex3 : hex7seg_t;",
            "    signal hex4 : hex7seg_t;",
            "    signal hex5 : hex7seg_t;",
            "",
            "    signal vga_r  : std_logic_vector(3 downto 0);",
            "    signal vga_g  : std_logic_vector(3 downto 0);",
            "    signal vga_b  : std_logic_vector(3 downto 0);",
            "    signal vga_hs : std_logic;",
            "    signal vga_vs : std_logic;",
            "",
            "    signal reset_sistema_s      : std_logic := '0';",
            "    signal escrita_habilitada_s : std_logic := '0';",
            "    signal limpa_canvas_pulso_s : std_logic := '0';",
            "    signal classifica_pulso_s   : std_logic := '0';",
            "",
            "    signal frame_recebido_s        : imagem_mnist_t := (others => '0');",
            "    signal frame_recebido_valido_s : std_logic := '0';",
            "",
            "    signal uart_recebendo_s    : std_logic := '0';",
            "    signal pacote_ok_pulso_s   : std_logic := '0';",
            "    signal pacote_erro_pulso_s : std_logic := '0';",
            "    signal erro_codigo_s       : uart_erro_t := UART_ERRO_NENHUM_C;",
            "    signal seq_ultimo_s        : uart_seq_t := (others => '0');",
            "",
            "    signal imagem_canvas_s         : imagem_mnist_t := (others => '0');",
            "    signal imagem_valida_s         : std_logic := '0';",
            "    signal imagem_alterada_pulso_s : std_logic := '0';",
            "",
            "    signal inicia_denso_s       : std_logic := '0';",
            "    signal registra_resultado_s : std_logic := '0';",
            "    signal limpa_resultado_s    : std_logic := '0';",
            "    signal denso_pronto_s       : std_logic := '0';",
            "",
            "    signal classificacao_ocupada_s : std_logic := '0';",
            "    signal resultado_pendente_s    : std_logic := '0';",
            "    signal estado_uc_s             : estado_uc_t := UC_IDLE_C;",
            "",
            "    signal digito_binario_s : digito_t := (others => '0');",
            "    signal digito_denso_s   : digito_t := (others => '0');",
            "",
            "    signal resultado_valido_s : std_logic := '0';",
            "    signal classificadores_concordam_s : std_logic := '0';",
            "",
        ]
    )

    if with_vga:
        lines.extend(
            [
                (
                    "    constant TB_VGA_LOG_PATH_C : string := "
                    f"\"{vhdl_string(vhdl_path(vga_log_path(session_path)))}\";"
                ),
                "",
                "    signal pixel_tick_capture_s : std_logic := '0';",
                "    signal x_capture_s          : vga_coord_t := (others => '0');",
                "    signal y_capture_s          : vga_coord_t := (others => '0');",
                "    signal video_on_capture_s   : std_logic := '0';",
                "",
            ]
        )


def emit_payload_constants(lines: list[str], events: list[dict[str, Any]]) -> None:
    emitted_snapshot_indices: set[int] = set()

    for event in events:
        if is_uart_frame_event(event):
            lines.extend(vhdl_payload_constant(event["_payload_const"], event["_payload"]))
            lines.append("")
        elif event["type"] == EVENT_SNAPSHOT:
            snapshot_index = event["snapshot_index"]
            if snapshot_index in emitted_snapshot_indices:
                continue
            emitted_snapshot_indices.add(snapshot_index)
            lines.extend(vhdl_payload_constant(event["_payload_const"], event["_payload"]))
            lines.append(
                f"    constant {event['_image_const']} : imagem_mnist_t :="
            )
            lines.append(f"        tb_payload_to_image({event['_payload_const']});")
            lines.append("")


def emit_observation_helpers(lines: list[str]) -> None:
    lines.extend(
        [
            "    function count_pixels(image : imagem_mnist_t) return natural is",
            "        variable total_v : natural := 0;",
            "    begin",
            "        for i in image'range loop",
            "            if image(i) = '1' then",
            "                total_v := total_v + 1;",
            "            end if;",
            "        end loop;",
            "",
            "        return total_v;",
            "    end function;",
            "",
            "    procedure report_signal_change(",
            "        name      : in string;",
            "        old_value : in std_logic;",
            "        new_value : in std_logic",
            "    ) is",
            "    begin",
            "        if old_value /= new_value then",
            "            report \"MON \" & name & \": \" & std_logic'image(old_value) &",
            "                   \" -> \" & std_logic'image(new_value)",
            "                severity note;",
            "        end if;",
            "    end procedure;",
            "",
        ]
    )


def emit_vga_capture_instances(lines: list[str]) -> None:
    lines.extend(
        [
            "    u_vga_capture_clock : entity work.divisor_clock_25mhz",
            "        port map (",
            "            clock_50      => clock_50,",
            "            reset         => reset_sistema_s,",
            "            pixel_tick_25 => pixel_tick_capture_s",
            "        );",
            "",
            "    u_vga_capture_sync : entity work.vga_sync_640x480",
            "        port map (",
            "            clock      => clock_50,",
            "            reset      => reset_sistema_s,",
            "            pixel_tick => pixel_tick_capture_s,",
            "            x_pixel    => x_capture_s,",
            "            y_pixel    => y_capture_s,",
            "            video_on   => video_on_capture_s,",
            "            hsync      => open,",
            "            vsync      => open",
            "        );",
            "",
        ]
    )


def emit_instances(lines: list[str], with_vga: bool) -> None:
    lines.extend(
        [
            "begin",
            "",
            "    clock_50 <= not clock_50 after TB_CLK_PERIOD_C / 2;",
            "",
        ]
    )

    lines.extend(
        [
            "    reset_sistema_s <= '0';",
            "",
            "    u_interface_entrada : entity work.interface_entrada",
            "        port map (",
            "            clock              => clock_50,",
            "            escreve            => escreve,",
            "            apaga              => apaga,",
            "            classifica         => classifica,",
            "            escrita_habilitada => escrita_habilitada_s,",
            "            limpa_canvas_pulso => limpa_canvas_pulso_s,",
            "            classifica_pulso   => classifica_pulso_s",
            "        );",
            "",
            "    u_uart_frontend : entity work.uart_frontend",
            "        port map (",
            "            clock                  => clock_50,",
            "            reset                  => reset_sistema_s,",
            "            uart_rx_serial         => uart_rx_serial,",
            "            uart_tx_serial         => uart_tx_serial,",
            "            frame_recebido         => frame_recebido_s,",
            "            frame_recebido_valido  => frame_recebido_valido_s,",
            "            uart_recebendo         => uart_recebendo_s,",
            "            pacote_ok_pulso        => pacote_ok_pulso_s,",
            "            pacote_erro_pulso      => pacote_erro_pulso_s,",
            "            erro_codigo            => erro_codigo_s,",
            "            seq_ultimo             => seq_ultimo_s",
            "        );",
            "",
        ]
    )

    lines.extend(
        [
            "    u_mnist_canvas : entity work.mnist_canvas",
            "        port map (",
            "            clock                  => clock_50,",
            "            reset                  => reset_sistema_s,",
            "            limpa_canvas_pulso     => limpa_canvas_pulso_s,",
            "            escrita_habilitada     => escrita_habilitada_s,",
            "            frame_recebido         => frame_recebido_s,",
            "            frame_recebido_valido  => frame_recebido_valido_s,",
            "            imagem_atual           => imagem_canvas_s,",
            "            imagem_valida          => imagem_valida_s,",
            "            imagem_alterada_pulso  => imagem_alterada_pulso_s",
            "        );",
            "",
            "    u_mnist_uc : entity work.mnist_uc",
            "        port map (",
            "            clock                  => clock_50,",
            "            reset                  => reset_sistema_s,",
            "            classifica_pulso       => classifica_pulso_s,",
            "            limpa_canvas_pulso     => limpa_canvas_pulso_s,",
            "            imagem_alterada_pulso  => imagem_alterada_pulso_s,",
            "            escrita_habilitada     => escrita_habilitada_s,",
            "            imagem_valida          => imagem_valida_s,",
            "            denso_pronto           => denso_pronto_s,",
            "            inicia_denso           => inicia_denso_s,",
            "            registra_resultado     => registra_resultado_s,",
            "            limpa_resultado        => limpa_resultado_s,",
            "            classificacao_ocupada  => classificacao_ocupada_s,",
            "            resultado_pendente     => resultado_pendente_s,",
            "            estado_uc              => estado_uc_s",
            "        );",
            "",
            "    u_mnist_fd : entity work.mnist_fd",
            "        port map (",
            "            clock                    => clock_50,",
            "            reset                    => reset_sistema_s,",
            "            imagem                   => imagem_canvas_s,",
            "            inicia_denso             => inicia_denso_s,",
            "            registra_resultado       => registra_resultado_s,",
            "            limpa_resultado          => limpa_resultado_s,",
            "            denso_pronto             => denso_pronto_s,",
            "            digito_binario           => digito_binario_s,",
            "            digito_denso             => digito_denso_s,",
            "            resultado_valido         => resultado_valido_s,",
            "            classificadores_concordam => classificadores_concordam_s",
            "        );",
            "",
            "    u_interface_saida : entity work.interface_saida",
            "        port map (",
            "            clock                    => clock_50,",
            "            reset                    => reset_sistema_s,",
            "            limpa_canvas_pulso       => limpa_canvas_pulso_s,",
            "            escrita_habilitada       => escrita_habilitada_s,",
            "            imagem_valida            => imagem_valida_s,",
            "            uart_recebendo           => uart_recebendo_s,",
            "            pacote_ok_pulso          => pacote_ok_pulso_s,",
            "            pacote_erro_pulso        => pacote_erro_pulso_s,",
            "            erro_codigo              => erro_codigo_s,",
            "            classificacao_ocupada    => classificacao_ocupada_s,",
            "            resultado_valido         => resultado_valido_s,",
            "            classificadores_concordam => classificadores_concordam_s,",
            "            digito_binario           => digito_binario_s,",
            "            digito_denso             => digito_denso_s,",
            "            estado_uc                => estado_uc_s,",
            "            ledr                     => ledr,",
            "            hex0                     => hex0,",
            "            hex1                     => hex1,",
            "            hex2                     => hex2,",
            "            hex3                     => hex3,",
            "            hex4                     => hex4,",
            "            hex5                     => hex5",
            "        );",
            "",
        ]
    )

    if with_vga:
        lines.extend(
            [
                "    u_vga_top : entity work.vga_top",
                "        port map (",
                "            clock_50                 => clock_50,",
                "            reset                    => reset_sistema_s,",
                "            imagem                   => imagem_canvas_s,",
                "            escrita_habilitada       => escrita_habilitada_s,",
                "            imagem_valida            => imagem_valida_s,",
                "            uart_recebendo           => uart_recebendo_s,",
                "            pacote_ok_pulso          => pacote_ok_pulso_s,",
                "            pacote_erro_pulso        => pacote_erro_pulso_s,",
                "            erro_codigo              => erro_codigo_s,",
                "            classificacao_ocupada    => classificacao_ocupada_s,",
                "            resultado_valido         => resultado_valido_s,",
                "            classificadores_concordam => classificadores_concordam_s,",
                "            digito_binario           => digito_binario_s,",
                "            digito_denso             => digito_denso_s,",
                "            estado_uc                => estado_uc_s,",
                "            vga_r                    => vga_r,",
                "            vga_g                    => vga_g,",
                "            vga_b                    => vga_b,",
                "            vga_hs                   => vga_hs,",
                "            vga_vs                   => vga_vs",
                "        );",
                "",
            ]
        )
        emit_vga_capture_instances(lines)


def emit_monitor_process(lines: list[str], verbose: bool) -> None:
    if not verbose:
        return

    lines.extend(
        [
            "    monitor : process(clock_50)",
            "        variable prev_reset_v      : std_logic := '0';",
            "        variable prev_escrita_v    : std_logic := '0';",
            "        variable prev_img_valida_v : std_logic := '0';",
            "        variable prev_result_v     : std_logic := '0';",
            "        variable prev_busy_v       : std_logic := '0';",
            "        variable prev_denso_v      : std_logic := '0';",
            "        variable prev_estado_v     : estado_uc_t := UC_IDLE_C;",
            "        variable prev_seq_v        : uart_seq_t := (others => '0');",
            "        variable prev_erro_v       : uart_erro_t := UART_ERRO_NENHUM_C;",
            "    begin",
            "        if rising_edge(clock_50) then",
            "            report_signal_change(\"reset_sistema_s\", prev_reset_v, reset_sistema_s);",
            "            report_signal_change(\"escrita_habilitada_s\", prev_escrita_v, escrita_habilitada_s);",
            "            report_signal_change(\"imagem_valida_s\", prev_img_valida_v, imagem_valida_s);",
            "            report_signal_change(\"resultado_valido_s\", prev_result_v, resultado_valido_s);",
            "            report_signal_change(\"classificacao_ocupada_s\", prev_busy_v, classificacao_ocupada_s);",
            "",
            "            if estado_uc_s /= prev_estado_v then",
            "                report \"MON estado_uc_s: \" &",
            "                       integer'image(to_integer(unsigned(prev_estado_v))) &",
            "                       \" -> \" & integer'image(to_integer(unsigned(estado_uc_s)))",
            "                    severity note;",
            "            end if;",
            "",
            "            if seq_ultimo_s /= prev_seq_v then",
            "                report \"MON seq_ultimo_s: 0x\" & to_hstring(prev_seq_v) &",
            "                       \" -> 0x\" & to_hstring(seq_ultimo_s)",
            "                    severity note;",
            "            end if;",
            "",
            "            if erro_codigo_s /= prev_erro_v then",
            "                report \"MON erro_codigo_s: 0x\" & to_hstring(prev_erro_v) &",
            "                       \" -> 0x\" & to_hstring(erro_codigo_s)",
            "                    severity note;",
            "            end if;",
            "",
            "            if limpa_canvas_pulso_s = '1' then",
            "                report \"MON limpa_canvas_pulso_s\" severity note;",
            "            end if;",
            "",
            "            if classifica_pulso_s = '1' then",
            "                report \"MON classifica_pulso_s\" severity note;",
            "            end if;",
            "",
            "            if frame_recebido_valido_s = '1' then",
            "                report \"MON frame_recebido_valido_s pixels=\" &",
            "                       integer'image(count_pixels(frame_recebido_s))",
            "                    severity note;",
            "            end if;",
            "",
            "            if pacote_ok_pulso_s = '1' then",
            "                report \"MON pacote_ok_pulso_s seq=0x\" & to_hstring(seq_ultimo_s)",
            "                    severity note;",
            "            end if;",
            "",
            "            if pacote_erro_pulso_s = '1' then",
            "                report \"MON pacote_erro_pulso_s erro=0x\" & to_hstring(erro_codigo_s)",
            "                    severity warning;",
            "            end if;",
            "",
            "            if imagem_alterada_pulso_s = '1' then",
            "                report \"MON imagem_alterada_pulso_s pixels_canvas=\" &",
            "                       integer'image(count_pixels(imagem_canvas_s))",
            "                    severity note;",
            "            end if;",
            "",
            "            if inicia_denso_s = '1' then",
            "                report \"MON inicia_denso_s pixels_canvas=\" &",
            "                       integer'image(count_pixels(imagem_canvas_s))",
            "                    severity note;",
            "            end if;",
            "",
            "            if denso_pronto_s = '1' and prev_denso_v = '0' then",
            "                report \"MON denso_pronto_s\" severity note;",
            "            end if;",
            "",
            "            if registra_resultado_s = '1' then",
            "                report \"MON registra_resultado_s bin=\" &",
            "                       integer'image(to_integer(digito_binario_s)) &",
            "                       \" denso=\" & integer'image(to_integer(digito_denso_s)) &",
            "                       \" concordam=\" & std_logic'image(classificadores_concordam_s)",
            "                    severity note;",
            "            end if;",
            "",
            "            prev_reset_v      := reset_sistema_s;",
            "            prev_escrita_v    := escrita_habilitada_s;",
            "            prev_img_valida_v := imagem_valida_s;",
            "            prev_result_v     := resultado_valido_s;",
            "            prev_busy_v       := classificacao_ocupada_s;",
            "            prev_denso_v      := denso_pronto_s;",
            "            prev_estado_v     := estado_uc_s;",
            "            prev_seq_v        := seq_ultimo_s;",
            "            prev_erro_v       := erro_codigo_s;",
            "        end if;",
            "    end process;",
            "",
        ]
    )


def emit_vga_capture_helpers(lines: list[str]) -> None:
    lines.extend(
        [
            "        function decimal_digit_char(value : natural) return character is",
            "        begin",
            "            case value is",
            "                when 0 => return '0';",
            "                when 1 => return '1';",
            "                when 2 => return '2';",
            "                when 3 => return '3';",
            "                when 4 => return '4';",
            "                when 5 => return '5';",
            "                when 6 => return '6';",
            "                when 7 => return '7';",
            "                when 8 => return '8';",
            "                when 9 => return '9';",
            "                when others => return '?';",
            "            end case;",
            "        end function;",
            "",
            "        function hex_digit_char(value : std_logic_vector(3 downto 0)) return character is",
            "            variable index_v : natural := to_integer(unsigned(value));",
            "        begin",
            "            case index_v is",
            "                when 0  => return '0';",
            "                when 1  => return '1';",
            "                when 2  => return '2';",
            "                when 3  => return '3';",
            "                when 4  => return '4';",
            "                when 5  => return '5';",
            "                when 6  => return '6';",
            "                when 7  => return '7';",
            "                when 8  => return '8';",
            "                when 9  => return '9';",
            "                when 10 => return 'A';",
            "                when 11 => return 'B';",
            "                when 12 => return 'C';",
            "                when 13 => return 'D';",
            "                when 14 => return 'E';",
            "                when 15 => return 'F';",
            "                when others => return 'X';",
            "            end case;",
            "        end function;",
            "",
            "        procedure write_padded_natural(",
            "            variable row_v : inout line;",
            "            value          : in natural;",
            "            width          : in positive",
            "        ) is",
            "            variable divisor_v : natural := 1;",
            "            variable digit_v   : natural := 0;",
            "        begin",
            "            for i in 2 to width loop",
            "                divisor_v := divisor_v * 10;",
            "            end loop;",
            "",
            "            for i in 1 to width loop",
            "                digit_v := (value / divisor_v) mod 10;",
            "                write(row_v, decimal_digit_char(digit_v));",
            "                if divisor_v > 1 then",
            "                    divisor_v := divisor_v / 10;",
            "                end if;",
            "            end loop;",
            "        end procedure;",
            "",
            "        procedure write_rgb444(",
            "            variable row_v : inout line;",
            "            red            : in std_logic_vector(3 downto 0);",
            "            green          : in std_logic_vector(3 downto 0);",
            "            blue           : in std_logic_vector(3 downto 0)",
            "        ) is",
            "        begin",
            "            write(row_v, hex_digit_char(red));",
            "            write(row_v, hex_digit_char(green));",
            "            write(row_v, hex_digit_char(blue));",
            "        end procedure;",
            "",
            "        procedure wait_for_visible_vga_pixel is",
            "        begin",
            "            loop",
            "                wait until rising_edge(clock_50);",
            "                wait for 1 ns;",
            "                exit when pixel_tick_capture_s = '1' and video_on_capture_s = '1';",
            "            end loop;",
            "        end procedure;",
            "",
            "        procedure capture_vga_snapshot(",
            "            kind     : in string;",
            "            event_id : in natural",
            "        ) is",
            "            variable line_v : line;",
            "        begin",
            "            report \"VGA aguardando snapshot \" & kind & \" evento \" &",
            "                   integer'image(event_id)",
            "                severity note;",
            "",
            "            loop",
            "                wait_for_visible_vga_pixel;",
            "                exit when to_integer(x_capture_s) = 0 and",
            "                          to_integer(y_capture_s) = 0;",
            "            end loop;",
            "",
            "            write(line_v, string'(\"BEGIN_SNAPSHOT kind=\"));",
            "            write(line_v, kind);",
            "            write(line_v, string'(\" event=\"));",
            "            write_padded_natural(line_v, event_id, 4);",
            "            write(line_v, string'(\" width=640 height=480\"));",
            "            writeline(vga_log_file, line_v);",
            "",
            "            for y in 0 to VGA_V_VISIBLE_C - 1 loop",
            "                write(line_v, string'(\"ROW \"));",
            "                write_padded_natural(line_v, y, 3);",
            "",
            "                for x in 0 to VGA_H_VISIBLE_C - 1 loop",
            "                    write(line_v, string'(\" \"));",
            "                    write_rgb444(line_v, vga_r, vga_g, vga_b);",
            "",
            "                    if not (x = VGA_H_VISIBLE_C - 1 and",
            "                            y = VGA_V_VISIBLE_C - 1) then",
            "                        wait_for_visible_vga_pixel;",
            "                    end if;",
            "                end loop;",
            "",
            "                writeline(vga_log_file, line_v);",
            "            end loop;",
            "",
            "            write(line_v, string'(\"END_SNAPSHOT\"));",
            "            writeline(vga_log_file, line_v);",
            "            report \"VGA snapshot \" & kind & \" evento \" &",
            "                   integer'image(event_id) & \" salvo em \" & TB_VGA_LOG_PATH_C",
            "                severity note;",
            "        end procedure;",
            "",
        ]
    )


def emit_process_header(lines: list[str], session_path: Path, with_vga: bool) -> None:
    lines.extend(
        [
            "    stim : process",
            "        variable expected_canvas_v : imagem_mnist_t := (others => '0');",
            "        variable escreve_model_v : std_logic := '0';",
            "",
        ]
    )

    if with_vga:
        lines.extend(
            [
                "        file vga_log_file : text open write_mode is TB_VGA_LOG_PATH_C;",
                "",
            ]
        )
        emit_vga_capture_helpers(lines)

    lines.extend(
        [
            "        procedure observe_uart_byte(",
            "            signal rx_serial : in std_logic;",
            "            variable value   : out uart_byte_t;",
            "            variable ok      : out boolean",
            "        ) is",
            "        begin",
            "            ok := true;",
            "",
            "            if rx_serial /= '0' then",
            "                wait until rx_serial = '0';",
            "            end if;",
            "",
            "            wait for TB_BIT_TIME_C + TB_BIT_TIME_C / 2;",
            "",
            "            for i in 0 to 7 loop",
            "                value(i) := rx_serial;",
            "                wait for TB_BIT_TIME_C;",
            "            end loop;",
            "",
            "            if rx_serial /= '1' then",
            "                ok := false;",
            "                report \"OBS stop bit de uart_tx_serial nao ficou alto\" severity warning;",
            "            end if;",
            "",
            "            wait for TB_BIT_TIME_C / 2;",
            "        end procedure;",
            "",
            "        procedure wait_control_sync is",
            "        begin",
            "            tb_wait_cycles(clock_50, TB_CONTROL_SYNC_WAIT_C);",
            "        end procedure;",
            "",
            "        procedure pulse_apaga(",
            "            msg : in string",
            "        ) is",
            "        begin",
            "            report \"OBS \" & msg & \": pulso de apaga\" severity note;",
            "            apaga <= '1';",
            "            wait_control_sync;",
            "            apaga <= '0';",
            "            wait_control_sync;",
            "        end procedure;",
            "",
            "        procedure pulse_classifica_and_wait(",
            "            timeout_cycles : in natural;",
            "            msg            : in string",
            "        ) is",
            "            variable seen_v           : boolean := false;",
            "            variable observed_after_v : natural := 0;",
            "            variable elapsed_v        : natural := 0;",
            "        begin",
            "            report \"OBS \" & msg & \": pulso de classifica\" severity note;",
            "            classifica <= '1';",
            "",
            "            for i in 1 to TB_CONTROL_SYNC_WAIT_C loop",
            "                wait until rising_edge(clock_50);",
            "                wait for 1 ns;",
            "",
            "                if (not seen_v) and registra_resultado_s = '1' then",
            "                    seen_v := true;",
            "                    observed_after_v := elapsed_v;",
            "                end if;",
            "",
            "                elapsed_v := elapsed_v + 1;",
            "            end loop;",
            "",
            "            classifica <= '0';",
            "",
            "            for i in 1 to TB_CONTROL_SYNC_WAIT_C + 4 loop",
            "                wait until rising_edge(clock_50);",
            "                wait for 1 ns;",
            "",
            "                if (not seen_v) and registra_resultado_s = '1' then",
            "                    seen_v := true;",
            "                    observed_after_v := elapsed_v;",
            "                end if;",
            "",
            "                elapsed_v := elapsed_v + 1;",
            "            end loop;",
            "",
            "            if not seen_v then",
            "                for i in 0 to timeout_cycles loop",
            "                    wait until rising_edge(clock_50);",
            "                    wait for 1 ns;",
            "",
            "                    if registra_resultado_s = '1' then",
            "                        seen_v := true;",
            "                        observed_after_v := elapsed_v;",
            "                        exit;",
            "                    end if;",
            "",
            "                    elapsed_v := elapsed_v + 1;",
            "                end loop;",
            "            end if;",
            "",
            "            if seen_v then",
            "                if TB_VERBOSE_C then",
            "                    report \"OBS \" & msg & \": registra_resultado_s observado apos \" &",
            "                           integer'image(observed_after_v) & \" ciclos\"",
            "                        severity note;",
            "                end if;",
            "",
            "                wait until rising_edge(clock_50);",
            "                wait for 1 ns;",
            "",
            "                if TB_VERBOSE_C then",
            "                    report \"OBS \" & msg & \": resultado_valido_s=\" &",
            "                           std_logic'image(resultado_valido_s)",
            "                        severity note;",
            "                end if;",
            "            else",
            "                report \"OBS \" & msg & \": registra_resultado_s nao observado na janela\"",
            "                    severity warning;",
            "            end if;",
            "        end procedure;",
            "",
            "        procedure set_escreve(",
            "            value : in std_logic;",
            "            msg   : in string",
            "        ) is",
            "        begin",
            "            escreve <= value;",
            "            wait_control_sync;",
            "            report \"OBS \" & msg & \": escreve=\" & std_logic'image(value)",
            "                severity note;",
            "            if escrita_habilitada_s /= value then",
            "                report \"OBS escreve solicitado \" & std_logic'image(value) &",
            "                       \", observado escrita_habilitada_s=\" &",
            "                       std_logic'image(escrita_habilitada_s)",
            "                    severity warning;",
            "            elsif TB_VERBOSE_C then",
            "                report \"OBS escreve observado escrita_habilitada_s=\" &",
            "                       std_logic'image(escrita_habilitada_s)",
            "                    severity note;",
            "            end if;",
            "        end procedure;",
            "",
            ]
        )
    lines.extend(
        [
            "        procedure observe_canvas(",
            "            expected : in imagem_mnist_t;",
            "            msg      : in string",
            "        ) is",
            "        begin",
            "            report \"OBS \" & msg & \": pixels_esperados=\" &",
            "                   integer'image(count_pixels(expected)) &",
            "                   \" pixels_observados=\" &",
            "                   integer'image(count_pixels(imagem_canvas_s))",
            "                severity note;",
            "",
            "            if TB_REPORT_CANVAS_DIFFS_C and imagem_canvas_s /= expected then",
            "                report \"OBS \" & msg & \": imagem_canvas_s difere do modelo JSON\"",
            "                    severity warning;",
            "            end if;",
            "        end procedure;",
            "",
            "        procedure observe_classification_registered(",
            "            timeout_cycles : in natural;",
            "            msg            : in string",
            "        ) is",
            "        begin",
            "            for i in 0 to timeout_cycles loop",
            "                wait until rising_edge(clock_50);",
            "                wait for 1 ns;",
            "",
            "                if registra_resultado_s = '1' then",
            "                    if TB_VERBOSE_C then",
            "                        report \"OBS \" & msg & \": registra_resultado_s observado apos \" &",
            "                               integer'image(i) & \" ciclos\"",
            "                            severity note;",
            "                    end if;",
            "                    wait until rising_edge(clock_50);",
            "                    wait for 1 ns;",
            "                    if TB_VERBOSE_C then",
            "                        report \"OBS \" & msg & \": resultado_valido_s=\" &",
            "                               std_logic'image(resultado_valido_s)",
            "                            severity note;",
            "                    end if;",
            "                    return;",
            "                end if;",
            "            end loop;",
            "",
            "            report \"OBS \" & msg & \": registra_resultado_s nao observado na janela\"",
            "                severity warning;",
            "        end procedure;",
            "",
            "        procedure report_classification(snapshot_name : in string) is",
            "        begin",
            "            report \"RESULTADO \" & snapshot_name &",
            "                   \": digito_binario=\" & integer'image(to_integer(digito_binario_s)) &",
            "                   \", digito_denso=\" & integer'image(to_integer(digito_denso_s)) &",
            "                   \", concordam=\" & std_logic'image(classificadores_concordam_s) &",
            "                   \", resultado_valido=\" & std_logic'image(resultado_valido_s)",
            "                severity note;",
            "        end procedure;",
            "",
        ]
    )

    lines.extend(
        [
            "        procedure send_logged_packet(",
            "            seq     : in uart_seq_t;",
            "            payload : in uart_frame_payload_t;",
            "            msg     : in string",
            "        ) is",
            "            variable packet_v    : uart_response_packet_t := (others => (others => '0'));",
            "            variable byte_v      : uart_byte_t := (others => '0');",
            "            variable byte_ok_v   : boolean := true;",
            "            variable start_seen_v : boolean := false;",
            "            variable ok_seen_v    : boolean := false;",
            "            variable err_seen_v   : boolean := false;",
            "        begin",
            "            if TB_VERBOSE_C then",
            "                report \"OBS \" & msg & \": enviando pixels_payload=\" &",
            "                       integer'image(count_pixels(tb_payload_to_image(payload)))",
            "                    severity note;",
            "            end if;",
            "            tb_send_uart_frame_packet(uart_rx_serial, seq, payload, x\"00\");",
            "",
            "            for i in 0 to 5000 loop",
            "                wait until rising_edge(clock_50);",
            "                wait for 1 ns;",
            "",
            "                if pacote_ok_pulso_s = '1' then",
            "                    ok_seen_v := true;",
            "                end if;",
            "",
            "                if pacote_erro_pulso_s = '1' then",
            "                    err_seen_v := true;",
            "                end if;",
            "",
            "                if ok_seen_v or err_seen_v then",
            "                    exit;",
            "                end if;",
            "            end loop;",
            "",
            "            if ok_seen_v then",
            "                report \"OBS \" & msg & \": pacote recebido OK seq=0x\" &",
            "                       to_hstring(seq_ultimo_s)",
            "                    severity note;",
            "            elsif err_seen_v then",
            "                report \"OBS \" & msg & \": pacote recebido ERRO codigo=0x\" &",
            "                       to_hstring(erro_codigo_s)",
            "                    severity warning;",
            "            else",
            "                report \"OBS \" & msg & \": pacote nao recebido ate o timeout\"",
            "                    severity warning;",
            "            end if;",
            "",
            "            if seq_ultimo_s /= seq then",
            "                report \"OBS \" & msg & \": seq_ultimo_s difere da seq do JSON\"",
            "                    severity warning;",
            "            end if;",
            "",
            "            if TB_VERBOSE_C then",
            "                for i in 0 to 20000 loop",
            "                    wait until rising_edge(clock_50);",
            "                    wait for 1 ns;",
            "",
            "                    if uart_tx_serial = '0' then",
            "                        start_seen_v := true;",
            "                        exit;",
            "                    end if;",
            "                end loop;",
            "",
            "                if start_seen_v then",
            "                    for i in packet_v'range loop",
            "                        observe_uart_byte(uart_tx_serial, byte_v, byte_ok_v);",
            "                        packet_v(i) := byte_v;",
            "                        if not byte_ok_v then",
            "                            report \"OBS \" & msg & \": byte UART TX \" &",
            "                                   integer'image(i) & \" teve aviso de frame\"",
            "                                severity warning;",
            "                        end if;",
            "                    end loop;",
            "",
            "                    report \"OBS \" & msg & \": resposta UART TX cmd=0x\" &",
            "                           to_hstring(packet_v(2)) & \" seq=0x\" &",
            "                           to_hstring(packet_v(5)) & \" erro=0x\" &",
            "                           to_hstring(packet_v(6)) & \" checksum=0x\" &",
            "                           to_hstring(packet_v(7))",
            "                        severity note;",
            "                else",
            "                    report \"OBS \" & msg & \": nenhuma resposta UART TX observada\"",
            "                        severity warning;",
            "                end if;",
            "            end if;",
            "",
            "            tb_wait_cycles(clock_50, TB_POST_PACKET_WAIT_C);",
            "        end procedure;",
            "",
        ]
    )

    lines.extend(
        [
            "    begin",
            (
                "        report \"tb_mnist_top inicio da sessao: "
                f"{vhdl_string(display_path(session_path))}\" severity note;"
            ),
        ]
    )

    lines.extend(
        [
            "        escreve <= '0';",
            "        apaga <= '0';",
            "        classifica <= '0';",
            "        uart_rx_serial <= '1';",
            "        tb_wait_cycles(clock_50, 10);",
            "",
            "        observe_canvas(expected_canvas_v, \"estado inicial\");",
            "",
        ]
    )


def classification_snapshot(
    events: list[dict[str, Any]],
    index: int,
) -> dict[str, Any] | None:
    if index > 0 and events[index - 1]["type"] == EVENT_SNAPSHOT:
        return events[index - 1]
    if index + 1 < len(events) and events[index + 1]["type"] == EVENT_SNAPSHOT:
        return events[index + 1]
    return None


def emit_event_actions(
    lines: list[str],
    events: list[dict[str, Any]],
    with_vga: bool,
) -> None:
    for event in events:
        event_index = event["_event_index"]
        event_type = event["type"]

        if event_type == EVENT_CONTROLE:
            bit = "'1'" if event["_value"] else "'0'"
            lines.extend(
                [
                    f"        -- evento {event_index}: escreve = {event['_value']}",
                    f"        set_escreve({bit}, \"evento {event_index} escreve\");",
                    f"        escreve_model_v := {bit};",
                    "",
                ]
            )

        elif is_uart_frame_event(event):
            const_name = event["_payload_const"]
            seq = event["_seq"]
            lines.extend(
                [
                    f"        -- evento {event_index}: pacote UART frame SEQ=0x{seq:02X}",
                    (
                        f"        send_logged_packet(x\"{seq:02X}\", {const_name}, "
                        f"\"evento {event_index} UART SEQ 0x{seq:02X}\");"
                    ),
                    "        if escreve_model_v = '1' then",
                    f"            expected_canvas_v := tb_payload_to_image({const_name});",
                    (
                        f"            observe_canvas(expected_canvas_v, "
                        f"\"evento {event_index} UART com escreve=1\");"
                    ),
                    "            if imagem_valida_s /= '1' then",
                    f"                report \"OBS evento {event_index}: imagem_valida_s nao esta alto apos escrita habilitada\"",
                    "                    severity warning;",
                    "            end if;",
                    "        else",
                    (
                        f"            observe_canvas(expected_canvas_v, "
                        f"\"evento {event_index} UART com escreve=0\");"
                    ),
                    "        end if;",
                    "",
                ]
            )

        elif event_type == EVENT_CONTROLE_PULSO:
            name = event["_name"]
            if name == "apaga":
                action_lines = [
                    f"        -- evento {event_index}: apaga",
                    f"        pulse_apaga(\"evento {event_index} apaga\");",
                    "        expected_canvas_v := (others => '0');",
                    f"        observe_canvas(expected_canvas_v, \"evento {event_index} apaga\");",
                    "        if imagem_valida_s /= '0' then",
                    f"            report \"OBS evento {event_index}: imagem_valida_s nao esta baixo apos apaga\"",
                    "                severity warning;",
                    "        end if;",
                ]
                if with_vga:
                    action_lines.append(
                        f"        capture_vga_snapshot(\"apaga\", {event_index});"
                    )
                action_lines.append("")
                lines.extend(action_lines)
            else:
                snapshot = classification_snapshot(events, event_index)
                if snapshot is not None:
                    snapshot_name = (
                        f"captura {snapshot['snapshot_index']}: "
                        f"{display_path(snapshot.get('path', ''))}"
                    )
                else:
                    snapshot_name = "sem captura"

                action_lines = [
                    f"        -- evento {event_index}: classifica",
                    (
                        "        pulse_classifica_and_wait("
                        f"TB_RESULT_TIMEOUT_C, \"evento {event_index} classifica\");"
                    ),
                    f"        report_classification(\"{vhdl_string(snapshot_name)}\");",
                ]
                if with_vga:
                    action_lines.append(
                        f"        capture_vga_snapshot(\"classifica\", {event_index});"
                    )
                action_lines.append("")
                lines.extend(action_lines)

        elif event_type == EVENT_SNAPSHOT:
            image_const = event["_image_const"]
            snapshot_index = event["snapshot_index"]
            path = display_path(event.get("path", ""))
            lines.extend(
                [
                    f"        -- evento {event_index}: captura {snapshot_index}",
                    (
                        f"        observe_canvas({image_const}, "
                        f"\"captura {snapshot_index} canvas\");"
                    ),
                    "        if TB_VERBOSE_C then",
                    f"            report \"captura {snapshot_index} PNG: {vhdl_string(path)}\" severity note;",
                    "        end if;",
                    "",
                ]
            )


def emit_process_footer(lines: list[str]) -> None:
    lines.extend(
        [
            "        report \"tb_mnist_top concluido\" severity note;",
            "        stop;",
            "        wait;",
            "    end process;",
            "",
            "end architecture sim;",
            "",
        ]
    )


def generate_vhdl(
    events: list[dict[str, Any]],
    session_path: Path,
    with_vga: bool,
    verbose: bool,
) -> str:
    generated_at = datetime.now().isoformat(timespec="seconds")
    lines: list[str] = []

    emit_architecture_header(lines, session_path, generated_at, verbose, with_vga)
    emit_payload_constants(lines, events)
    emit_observation_helpers(lines)
    emit_instances(lines, with_vga)
    emit_monitor_process(lines, verbose)
    emit_process_header(lines, session_path, with_vga)
    emit_event_actions(lines, events, with_vga)
    emit_process_footer(lines)

    return "\n".join(lines)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Gera tb_mnist_top.vhd observacional a partir de uma sessao JSON."
    )
    parser.add_argument("session_json", help="caminho para session.json")
    parser.add_argument(
        "--out",
        required=True,
        help="arquivo VHDL de saida, por exemplo VHDL/testbenches/tb_mnist_top.vhd",
    )
    parser.add_argument(
        "--with-vga",
        action="store_true",
        help="instancia vga_top no testbench gerado (desligado por padrao)",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="reabilita monitores e logs detalhados no VHDL gerado",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    session_path = Path(args.session_json)
    out_path = Path(args.out)

    try:
        if not session_path.exists():
            fail(f"arquivo JSON nao existe: {session_path}")

        with session_path.open("r", encoding="utf-8") as fp:
            data = json.load(fp)

        events = validate_session(data, session_path)
        vhdl = generate_vhdl(
            events,
            session_path,
            with_vga=args.with_vga,
            verbose=args.verbose,
        )

        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(vhdl, encoding="utf-8")

    except json.JSONDecodeError as exc:
        print(f"Erro: JSON invalido em {session_path}: {exc}", file=sys.stderr)
        return 1
    except SessionError as exc:
        print(f"Erro: {exc}", file=sys.stderr)
        return 1
    except OSError as exc:
        print(f"Erro de arquivo: {exc}", file=sys.stderr)
        return 1

    print(f"Testbench gerado: {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

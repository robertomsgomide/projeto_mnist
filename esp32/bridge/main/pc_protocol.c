#include "pc_protocol.h"

#include <ctype.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include "esp_err.h"

#include "fpga_uart.h"
#include "gpio_ctrl.h"
#include "mnist_bridge_config.h"

typedef struct {
    uint32_t commands;
    uint32_t frames_sent;
    uint32_t ack_count;
    uint32_t nack_count;
    uint32_t error_count;
} pc_protocol_stats_t;

static pc_protocol_stats_t s_stats;

static void response_write(char *response, size_t response_size, const char *fmt, ...)
{
    if (response_size == 0) {
        return;
    }

    va_list args;
    va_start(args, fmt);
    (void)vsnprintf(response, response_size, fmt, args);
    va_end(args);
    response[response_size - 1] = '\0';
}

static void response_error(char *response, size_t response_size, const char *error)
{
    ++s_stats.error_count;
    response_write(response, response_size, "ERR %s", error);
}

static int hex_nibble(char ch)
{
    if (ch >= '0' && ch <= '9') {
        return ch - '0';
    }
    if (ch >= 'A' && ch <= 'F') {
        return ch - 'A' + 10;
    }
    if (ch >= 'a' && ch <= 'f') {
        return ch - 'a' + 10;
    }
    return -1;
}

static bool parse_hex_byte_exact(const char *text, uint8_t *value_out)
{
    if (text == NULL || value_out == NULL || strlen(text) != 2) {
        return false;
    }

    const int hi = hex_nibble(text[0]);
    const int lo = hex_nibble(text[1]);
    if (hi < 0 || lo < 0) {
        return false;
    }

    *value_out = (uint8_t)((hi << 4) | lo);
    return true;
}

static bool parse_payload_hex(const char *text, uint8_t payload[FPGA_UART_PAYLOAD_BYTES], bool *bad_len)
{
    if (bad_len != NULL) {
        *bad_len = false;
    }

    if (text == NULL || payload == NULL) {
        if (bad_len != NULL) {
            *bad_len = true;
        }
        return false;
    }

    if (strlen(text) != FPGA_UART_PAYLOAD_BYTES * 2U) {
        if (bad_len != NULL) {
            *bad_len = true;
        }
        return false;
    }

    for (size_t i = 0; i < FPGA_UART_PAYLOAD_BYTES; ++i) {
        const int hi = hex_nibble(text[i * 2U]);
        const int lo = hex_nibble(text[i * 2U + 1U]);
        if (hi < 0 || lo < 0) {
            return false;
        }
        payload[i] = (uint8_t)((hi << 4) | lo);
    }

    return true;
}

static bool no_extra_tokens(char **save_ptr)
{
    return strtok_r(NULL, " \t", save_ptr) == NULL;
}

static void format_fpga_result(
    const char *command_name,
    uint8_t seq,
    const fpga_uart_ack_t *ack,
    char *response,
    size_t response_size
)
{
    if (ack->result == FPGA_UART_RESULT_ACK) {
        ++s_stats.ack_count;
        response_write(response, response_size, "OK %s %02X ACK", command_name, seq);
        return;
    }

    ++s_stats.error_count;
    if (ack->result == FPGA_UART_RESULT_NACK) {
        ++s_stats.nack_count;
        response_write(
            response,
            response_size,
            "ERR %s %02X NACK %02X",
            command_name,
            seq,
            ack->error_code
        );
        return;
    }

    response_write(
        response,
        response_size,
        "ERR %s %02X %s",
        command_name,
        seq,
        fpga_uart_result_name(ack->result)
    );
}

static void handle_frame_command(
    const char *command_name,
    char *seq_text,
    char *payload_text,
    char **save_ptr,
    char *response,
    size_t response_size
)
{
    uint8_t seq = 0;
    uint8_t payload[FPGA_UART_PAYLOAD_BYTES] = {0};
    bool bad_len = false;

    if (seq_text == NULL || payload_text == NULL || !no_extra_tokens(save_ptr)) {
        response_error(response, response_size, "BAD_CMD");
        return;
    }

    if (!parse_hex_byte_exact(seq_text, &seq)) {
        response_error(response, response_size, "BAD_HEX");
        return;
    }

    if (!parse_payload_hex(payload_text, payload, &bad_len)) {
        response_error(response, response_size, bad_len ? "BAD_LEN" : "BAD_HEX");
        return;
    }

    esp_err_t err = fpga_uart_send_frame(seq, payload);
    if (err != ESP_OK) {
        ++s_stats.error_count;
        response_write(response, response_size, "ERR %s %02X IO_ERROR", command_name, seq);
        return;
    }

    ++s_stats.frames_sent;
    const fpga_uart_ack_t ack = fpga_uart_wait_ack(seq, MNIST_FPGA_ACK_TIMEOUT_MS);
    format_fpga_result(command_name, seq, &ack, response, response_size);
}

static void handle_fc_command(
    char *seq_text,
    char *payload_text,
    char **save_ptr,
    char *response,
    size_t response_size
)
{
    uint8_t seq = 0;
    uint8_t payload[FPGA_UART_PAYLOAD_BYTES] = {0};
    bool bad_len = false;

    if (seq_text == NULL || payload_text == NULL || !no_extra_tokens(save_ptr)) {
        response_error(response, response_size, "BAD_CMD");
        return;
    }

    if (!parse_hex_byte_exact(seq_text, &seq)) {
        response_error(response, response_size, "BAD_HEX");
        return;
    }

    if (!parse_payload_hex(payload_text, payload, &bad_len)) {
        response_error(response, response_size, bad_len ? "BAD_LEN" : "BAD_HEX");
        return;
    }

    if (gpio_ctrl_set_escreve(true) != ESP_OK) {
        ++s_stats.error_count;
        response_write(response, response_size, "ERR FC %02X GPIO", seq);
        return;
    }

    esp_err_t err = fpga_uart_send_frame(seq, payload);
    if (err != ESP_OK) {
        (void)gpio_ctrl_set_escreve(false);
        ++s_stats.error_count;
        response_write(response, response_size, "ERR FC %02X IO_ERROR", seq);
        return;
    }

    ++s_stats.frames_sent;
    const fpga_uart_ack_t ack = fpga_uart_wait_ack(seq, MNIST_FPGA_ACK_TIMEOUT_MS);
    (void)gpio_ctrl_set_escreve(false);

    if (ack.result == FPGA_UART_RESULT_ACK) {
        ++s_stats.ack_count;
        if (gpio_ctrl_pulse_classifica() != ESP_OK) {
            ++s_stats.error_count;
            response_write(response, response_size, "ERR FC %02X GPIO", seq);
            return;
        }
        response_write(response, response_size, "OK FC %02X ACK CLASSIFICA", seq);
        return;
    }

    ++s_stats.error_count;
    if (ack.result == FPGA_UART_RESULT_NACK) {
        ++s_stats.nack_count;
        response_write(response, response_size, "ERR FC %02X NACK %02X", seq, ack.error_code);
        return;
    }

    response_write(
        response,
        response_size,
        "ERR FC %02X %s",
        seq,
        fpga_uart_result_name(ack.result)
    );
}

void pc_protocol_handle_line(const char *line, char *response, size_t response_size)
{
    char copy[MNIST_PC_LINE_BUFFER_BYTES];

    if (line == NULL) {
        response_error(response, response_size, "BAD_CMD");
        return;
    }

    ++s_stats.commands;

    snprintf(copy, sizeof(copy), "%s", line);

    char *save_ptr = NULL;
    char *command = strtok_r(copy, " \t", &save_ptr);
    if (command == NULL) {
        response_error(response, response_size, "BAD_CMD");
        return;
    }

    for (char *p = command; *p != '\0'; ++p) {
        *p = (char)toupper((unsigned char)*p);
    }

    if (strcmp(command, "PING") == 0) {
        if (!no_extra_tokens(&save_ptr)) {
            response_error(response, response_size, "BAD_CMD");
            return;
        }
        response_write(response, response_size, "OK PONG");
        return;
    }

    if (strcmp(command, "STATUS") == 0) {
        if (!no_extra_tokens(&save_ptr)) {
            response_error(response, response_size, "BAD_CMD");
            return;
        }
        response_write(
            response,
            response_size,
            "OK STATUS E=%d FRAMES=%lu ACK=%lu NACK=%lu ERR=%lu",
            gpio_ctrl_get_escreve() ? 1 : 0,
            (unsigned long)s_stats.frames_sent,
            (unsigned long)s_stats.ack_count,
            (unsigned long)s_stats.nack_count,
            (unsigned long)s_stats.error_count
        );
        return;
    }

    if (strcmp(command, "E") == 0) {
        char *value_text = strtok_r(NULL, " \t", &save_ptr);
        if (value_text == NULL || !no_extra_tokens(&save_ptr)) {
            response_error(response, response_size, "BAD_CMD");
            return;
        }

        if (strcmp(value_text, "0") != 0 && strcmp(value_text, "1") != 0) {
            response_error(response, response_size, "BAD_CMD");
            return;
        }

        const bool value = (value_text[0] == '1');
        if (gpio_ctrl_set_escreve(value) != ESP_OK) {
            response_error(response, response_size, "GPIO");
            return;
        }

        response_write(response, response_size, "OK E %d", value ? 1 : 0);
        return;
    }

    if (strcmp(command, "A") == 0) {
        if (!no_extra_tokens(&save_ptr)) {
            response_error(response, response_size, "BAD_CMD");
            return;
        }
        if (gpio_ctrl_pulse_apaga() != ESP_OK) {
            response_error(response, response_size, "GPIO");
            return;
        }
        response_write(response, response_size, "OK A");
        return;
    }

    if (strcmp(command, "C") == 0) {
        if (!no_extra_tokens(&save_ptr)) {
            response_error(response, response_size, "BAD_CMD");
            return;
        }
        if (gpio_ctrl_pulse_classifica() != ESP_OK) {
            response_error(response, response_size, "GPIO");
            return;
        }
        response_write(response, response_size, "OK C");
        return;
    }

    if (strcmp(command, "F") == 0) {
        char *seq_text = strtok_r(NULL, " \t", &save_ptr);
        char *payload_text = strtok_r(NULL, " \t", &save_ptr);
        handle_frame_command(
            "F",
            seq_text,
            payload_text,
            &save_ptr,
            response,
            response_size
        );
        return;
    }

    if (strcmp(command, "FC") == 0) {
        char *seq_text = strtok_r(NULL, " \t", &save_ptr);
        char *payload_text = strtok_r(NULL, " \t", &save_ptr);
        handle_fc_command(
            seq_text,
            payload_text,
            &save_ptr,
            response,
            response_size
        );
        return;
    }

    response_error(response, response_size, "BAD_CMD");
}

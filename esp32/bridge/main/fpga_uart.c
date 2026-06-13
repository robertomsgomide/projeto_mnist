#include "fpga_uart.h"

#include <stdbool.h>
#include <stddef.h>

#include "driver/uart.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"

#include "mnist_bridge_config.h"

static uint8_t fpga_uart_checksum_frame(uint8_t seq, const uint8_t payload[FPGA_UART_PAYLOAD_BYTES])
{
    uint8_t checksum = FPGA_UART_CMD_FRAME ^ FPGA_UART_FRAME_LEN_L ^ FPGA_UART_FRAME_LEN_H ^ seq;

    for (size_t i = 0; i < FPGA_UART_PAYLOAD_BYTES; ++i) {
        checksum ^= payload[i];
    }

    return checksum;
}

static uint8_t fpga_uart_checksum_ack(uint8_t cmd, uint8_t seq, uint8_t error_code)
{
    return cmd ^ FPGA_UART_ACK_LEN_L ^ FPGA_UART_ACK_LEN_H ^ seq ^ error_code;
}

esp_err_t fpga_uart_init(void)
{
    const uart_config_t uart_config = {
        .baud_rate = MNIST_FPGA_UART_BAUD_RATE,
        .data_bits = UART_DATA_8_BITS,
        .parity = UART_PARITY_DISABLE,
        .stop_bits = UART_STOP_BITS_1,
        .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
        .rx_flow_ctrl_thresh = 0,
        .source_clk = UART_SCLK_DEFAULT,
    };

    esp_err_t err = uart_param_config(MNIST_FPGA_UART_PORT, &uart_config);
    if (err != ESP_OK) {
        return err;
    }

    err = uart_set_pin(
        MNIST_FPGA_UART_PORT,
        MNIST_FPGA_UART_TX_GPIO,
        MNIST_FPGA_UART_RX_GPIO,
        UART_PIN_NO_CHANGE,
        UART_PIN_NO_CHANGE
    );
    if (err != ESP_OK) {
        return err;
    }

    err = uart_driver_install(
        MNIST_FPGA_UART_PORT,
        MNIST_FPGA_UART_RX_BUFFER_BYTES,
        MNIST_FPGA_UART_TX_BUFFER_BYTES,
        0,
        NULL,
        0
    );
    if (err != ESP_OK) {
        return err;
    }

    uart_flush_input(MNIST_FPGA_UART_PORT);
    return ESP_OK;
}

esp_err_t fpga_uart_send_frame(uint8_t seq, const uint8_t payload[FPGA_UART_PAYLOAD_BYTES])
{
    if (payload == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    uint8_t packet[FPGA_UART_FRAME_PACKET_BYTES];
    size_t index = 0;

    packet[index++] = FPGA_UART_HEADER0;
    packet[index++] = FPGA_UART_HEADER1;
    packet[index++] = FPGA_UART_CMD_FRAME;
    packet[index++] = FPGA_UART_FRAME_LEN_L;
    packet[index++] = FPGA_UART_FRAME_LEN_H;
    packet[index++] = seq;

    for (size_t i = 0; i < FPGA_UART_PAYLOAD_BYTES; ++i) {
        packet[index++] = payload[i];
    }

    packet[index++] = fpga_uart_checksum_frame(seq, payload);

    uart_flush_input(MNIST_FPGA_UART_PORT);

    const int written = uart_write_bytes(
        MNIST_FPGA_UART_PORT,
        (const char *)packet,
        sizeof(packet)
    );
    if (written != (int)sizeof(packet)) {
        return ESP_FAIL;
    }

    return uart_wait_tx_done(MNIST_FPGA_UART_PORT, pdMS_TO_TICKS(100));
}

static fpga_uart_ack_t fpga_uart_make_result(fpga_uart_result_t result)
{
    fpga_uart_ack_t ack = {
        .result = result,
        .cmd = 0,
        .seq = 0,
        .error_code = 0,
        .checksum_expected = 0,
        .checksum_received = 0,
    };

    return ack;
}

static int fpga_uart_read_one_until(int64_t deadline_us, uint8_t *byte_out)
{
    while (esp_timer_get_time() < deadline_us) {
        int64_t remaining_us = deadline_us - esp_timer_get_time();
        if (remaining_us <= 0) {
            break;
        }

        uint32_t wait_ms = (uint32_t)((remaining_us + 999) / 1000);
        if (wait_ms == 0) {
            wait_ms = 1;
        }
        if (wait_ms > 20) {
            wait_ms = 20;
        }

        const int read = uart_read_bytes(
            MNIST_FPGA_UART_PORT,
            byte_out,
            1,
            pdMS_TO_TICKS(wait_ms)
        );

        if (read == 1) {
            return 1;
        }

        if (read < 0) {
            return -1;
        }
    }

    return 0;
}

fpga_uart_ack_t fpga_uart_wait_ack(uint8_t expected_seq, uint32_t timeout_ms)
{
    const int64_t deadline_us = esp_timer_get_time() + ((int64_t)timeout_ms * 1000);
    uint8_t byte = 0;
    bool saw_header0 = false;

    while (true) {
        const int read = fpga_uart_read_one_until(deadline_us, &byte);
        if (read == 0) {
            return fpga_uart_make_result(FPGA_UART_RESULT_TIMEOUT);
        }
        if (read < 0) {
            return fpga_uart_make_result(FPGA_UART_RESULT_IO_ERROR);
        }

        if (!saw_header0) {
            saw_header0 = (byte == FPGA_UART_HEADER0);
            continue;
        }

        if (byte == FPGA_UART_HEADER1) {
            break;
        }

        saw_header0 = (byte == FPGA_UART_HEADER0);
    }

    uint8_t fields[6] = {0};
    for (size_t i = 0; i < sizeof(fields); ++i) {
        const int read = fpga_uart_read_one_until(deadline_us, &fields[i]);
        if (read == 0) {
            return fpga_uart_make_result(FPGA_UART_RESULT_TIMEOUT);
        }
        if (read < 0) {
            return fpga_uart_make_result(FPGA_UART_RESULT_IO_ERROR);
        }
    }

    fpga_uart_ack_t ack = {
        .result = FPGA_UART_RESULT_ACK,
        .cmd = fields[0],
        .seq = fields[3],
        .error_code = fields[4],
        .checksum_expected = fpga_uart_checksum_ack(fields[0], fields[3], fields[4]),
        .checksum_received = fields[5],
    };

    if (ack.cmd != FPGA_UART_CMD_ACK && ack.cmd != FPGA_UART_CMD_NACK) {
        ack.result = FPGA_UART_RESULT_BAD_CMD;
        return ack;
    }

    if (fields[1] != FPGA_UART_ACK_LEN_L || fields[2] != FPGA_UART_ACK_LEN_H) {
        ack.result = FPGA_UART_RESULT_BAD_LEN;
        return ack;
    }

    if (ack.seq != expected_seq) {
        ack.result = FPGA_UART_RESULT_BAD_SEQ;
        return ack;
    }

    if (ack.checksum_received != ack.checksum_expected) {
        ack.result = FPGA_UART_RESULT_BAD_CHECKSUM;
        return ack;
    }

    ack.result = (ack.cmd == FPGA_UART_CMD_ACK) ? FPGA_UART_RESULT_ACK : FPGA_UART_RESULT_NACK;
    return ack;
}

const char *fpga_uart_result_name(fpga_uart_result_t result)
{
    switch (result) {
    case FPGA_UART_RESULT_ACK:
        return "ACK";
    case FPGA_UART_RESULT_NACK:
        return "NACK";
    case FPGA_UART_RESULT_TIMEOUT:
        return "TIMEOUT";
    case FPGA_UART_RESULT_BAD_CMD:
        return "BAD_CMD";
    case FPGA_UART_RESULT_BAD_LEN:
        return "BAD_LEN";
    case FPGA_UART_RESULT_BAD_SEQ:
        return "BAD_SEQ";
    case FPGA_UART_RESULT_BAD_CHECKSUM:
        return "BAD_CHECKSUM";
    case FPGA_UART_RESULT_IO_ERROR:
    default:
        return "IO_ERROR";
    }
}

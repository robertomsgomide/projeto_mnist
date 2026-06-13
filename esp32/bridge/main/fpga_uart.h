#pragma once

#include <stdint.h>

#include "esp_err.h"

#define FPGA_UART_HEADER0          0xA5U
#define FPGA_UART_HEADER1          0x5AU
#define FPGA_UART_CMD_FRAME        0x01U
#define FPGA_UART_CMD_ACK          0x06U
#define FPGA_UART_CMD_NACK         0x15U
#define FPGA_UART_FRAME_LEN_L      0x62U
#define FPGA_UART_FRAME_LEN_H      0x00U
#define FPGA_UART_ACK_LEN_L        0x01U
#define FPGA_UART_ACK_LEN_H        0x00U
#define FPGA_UART_PAYLOAD_BYTES    98U
#define FPGA_UART_FRAME_PACKET_BYTES (2U + 1U + 2U + 1U + FPGA_UART_PAYLOAD_BYTES + 1U)

typedef enum {
    FPGA_UART_RESULT_ACK = 0,
    FPGA_UART_RESULT_NACK,
    FPGA_UART_RESULT_TIMEOUT,
    FPGA_UART_RESULT_BAD_CMD,
    FPGA_UART_RESULT_BAD_LEN,
    FPGA_UART_RESULT_BAD_SEQ,
    FPGA_UART_RESULT_BAD_CHECKSUM,
    FPGA_UART_RESULT_IO_ERROR,
} fpga_uart_result_t;

typedef struct {
    fpga_uart_result_t result;
    uint8_t cmd;
    uint8_t seq;
    uint8_t error_code;
    uint8_t checksum_expected;
    uint8_t checksum_received;
} fpga_uart_ack_t;

esp_err_t fpga_uart_init(void);
esp_err_t fpga_uart_send_frame(uint8_t seq, const uint8_t payload[FPGA_UART_PAYLOAD_BYTES]);
fpga_uart_ack_t fpga_uart_wait_ack(uint8_t expected_seq, uint32_t timeout_ms);
const char *fpga_uart_result_name(fpga_uart_result_t result);

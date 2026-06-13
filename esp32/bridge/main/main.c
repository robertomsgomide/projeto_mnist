#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "driver/uart.h"
#include "esp_err.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "fpga_uart.h"
#include "gpio_ctrl.h"
#include "mnist_bridge_config.h"
#include "pc_protocol.h"

static esp_err_t pc_uart_init(void)
{
    const uart_config_t uart_config = {
        .baud_rate = MNIST_PC_UART_BAUD_RATE,
        .data_bits = UART_DATA_8_BITS,
        .parity = UART_PARITY_DISABLE,
        .stop_bits = UART_STOP_BITS_1,
        .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
        .rx_flow_ctrl_thresh = 0,
        .source_clk = UART_SCLK_DEFAULT,
    };

    esp_err_t err = uart_param_config(MNIST_PC_UART_PORT, &uart_config);
    if (err != ESP_OK) {
        return err;
    }

    err = uart_set_pin(
        MNIST_PC_UART_PORT,
        UART_PIN_NO_CHANGE,
        UART_PIN_NO_CHANGE,
        UART_PIN_NO_CHANGE,
        UART_PIN_NO_CHANGE
    );
    if (err != ESP_OK) {
        return err;
    }

    err = uart_driver_install(
        MNIST_PC_UART_PORT,
        MNIST_PC_UART_RX_BUFFER_BYTES,
        MNIST_PC_UART_TX_BUFFER_BYTES,
        0,
        NULL,
        0
    );
    if (err != ESP_OK) {
        return err;
    }

    uart_flush_input(MNIST_PC_UART_PORT);
    return ESP_OK;
}

static void pc_uart_write_line(const char *line)
{
    if (line == NULL) {
        return;
    }

    (void)uart_write_bytes(MNIST_PC_UART_PORT, line, strlen(line));
    (void)uart_write_bytes(MNIST_PC_UART_PORT, "\r\n", 2);
}

static void pc_uart_write_init_error(const char *name, esp_err_t err)
{
    char line[96];
    snprintf(line, sizeof(line), "ERR INIT %s 0x%X", name, (unsigned int)err);
    pc_uart_write_line(line);
}

void app_main(void)
{
    esp_log_level_set("*", ESP_LOG_NONE);

    esp_err_t err = pc_uart_init();
    if (err != ESP_OK) {
        return;
    }

    err = gpio_ctrl_init();
    if (err != ESP_OK) {
        pc_uart_write_init_error("GPIO", err);
        return;
    }

    err = fpga_uart_init();
    if (err != ESP_OK) {
        pc_uart_write_init_error("FPGA_UART", err);
        return;
    }

    pc_uart_write_line("LOG MNIST_BRIDGE_READY");

    char ready_line[112];
    snprintf(
        ready_line,
        sizeof(ready_line),
        "LOG PC_UART=%d FPGA_UART=%d PC_BAUD=%d FPGA_BAUD=%d",
        (int)MNIST_PC_UART_PORT,
        (int)MNIST_FPGA_UART_PORT,
        MNIST_PC_UART_BAUD_RATE,
        MNIST_FPGA_UART_BAUD_RATE
    );
    pc_uart_write_line(ready_line);

    char line[MNIST_PC_LINE_BUFFER_BYTES];
    size_t line_len = 0;
    bool line_overflow = false;

    while (true) {
        uint8_t byte = 0;
        const int read = uart_read_bytes(
            MNIST_PC_UART_PORT,
            &byte,
            1,
            pdMS_TO_TICKS(100)
        );

        if (read <= 0) {
            continue;
        }

        if (byte == '\r' || byte == '\n') {
            if (line_overflow) {
                pc_uart_write_line("ERR LINE_TOO_LONG");
                line_len = 0;
                line_overflow = false;
                continue;
            }

            if (line_len == 0) {
                continue;
            }

            line[line_len] = '\0';

            char response[160];
            pc_protocol_handle_line(line, response, sizeof(response));
            pc_uart_write_line(response);

            line_len = 0;
            continue;
        }

        if (line_overflow) {
            continue;
        }

        if (line_len >= sizeof(line) - 1U) {
            line_len = 0;
            line_overflow = true;
            continue;
        }

        line[line_len++] = (char)byte;
    }
}

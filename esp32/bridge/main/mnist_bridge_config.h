#pragma once

#include "driver/gpio.h"
#include "driver/uart.h"

/*
 * Default integration settings for the ESP32-S3 <-> DE0-CV bridge.
 *
 * IMPORTANT:
 * These ESP32-S3 GPIO defaults are plausible starter values only. Check the
 * exact pinout of your ESP32-S3 board before wiring it to the DE0-CV. Keep the
 * ESP32 GND and DE0-CV GND connected together, and use only 3.3 V logic.
 */

#define MNIST_PC_UART_BAUD_RATE      1000000
#define MNIST_FPGA_UART_BAUD_RATE    1000000

#define MNIST_PC_UART_PORT           UART_NUM_0
#define MNIST_FPGA_UART_PORT         UART_NUM_1

#define MNIST_FPGA_UART_TX_GPIO      GPIO_NUM_17
#define MNIST_FPGA_UART_RX_GPIO      GPIO_NUM_18

#define MNIST_GPIO_ESCREVE           GPIO_NUM_4
#define MNIST_GPIO_APAGA             GPIO_NUM_5
#define MNIST_GPIO_CLASSIFICA        GPIO_NUM_6

#define MNIST_CTRL_PULSE_MS          50
#define MNIST_FPGA_ACK_TIMEOUT_MS    300

#define MNIST_PC_UART_RX_BUFFER_BYTES    1024
#define MNIST_PC_UART_TX_BUFFER_BYTES    1024
#define MNIST_FPGA_UART_RX_BUFFER_BYTES  256
#define MNIST_FPGA_UART_TX_BUFFER_BYTES  256

#define MNIST_PC_LINE_BUFFER_BYTES       256

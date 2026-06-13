#pragma once

#include <stdbool.h>

#include "esp_err.h"

esp_err_t gpio_ctrl_init(void);
esp_err_t gpio_ctrl_set_escreve(bool value);
bool gpio_ctrl_get_escreve(void);
esp_err_t gpio_ctrl_pulse_apaga(void);
esp_err_t gpio_ctrl_pulse_classifica(void);

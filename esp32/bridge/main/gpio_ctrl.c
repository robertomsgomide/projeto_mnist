#include "gpio_ctrl.h"

#include "driver/gpio.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "mnist_bridge_config.h"

static bool s_escreve_state;

static esp_err_t gpio_ctrl_set_level_checked(gpio_num_t gpio_num, uint32_t level)
{
    return gpio_set_level(gpio_num, level);
}

esp_err_t gpio_ctrl_init(void)
{
    const uint64_t pin_mask =
        (1ULL << MNIST_GPIO_ESCREVE) |
        (1ULL << MNIST_GPIO_APAGA) |
        (1ULL << MNIST_GPIO_CLASSIFICA);

    gpio_config_t io_conf = {
        .pin_bit_mask = pin_mask,
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };

    esp_err_t err = gpio_config(&io_conf);
    if (err != ESP_OK) {
        return err;
    }

    err = gpio_ctrl_set_level_checked(MNIST_GPIO_ESCREVE, 0);
    if (err != ESP_OK) {
        return err;
    }
    err = gpio_ctrl_set_level_checked(MNIST_GPIO_APAGA, 0);
    if (err != ESP_OK) {
        return err;
    }
    err = gpio_ctrl_set_level_checked(MNIST_GPIO_CLASSIFICA, 0);
    if (err != ESP_OK) {
        return err;
    }

    s_escreve_state = false;
    return ESP_OK;
}

esp_err_t gpio_ctrl_set_escreve(bool value)
{
    esp_err_t err = gpio_ctrl_set_level_checked(MNIST_GPIO_ESCREVE, value ? 1U : 0U);
    if (err == ESP_OK) {
        s_escreve_state = value;
    }
    return err;
}

bool gpio_ctrl_get_escreve(void)
{
    return s_escreve_state;
}

esp_err_t gpio_ctrl_pulse_apaga(void)
{
    esp_err_t err = gpio_ctrl_set_level_checked(MNIST_GPIO_APAGA, 1);
    if (err != ESP_OK) {
        return err;
    }
    vTaskDelay(pdMS_TO_TICKS(MNIST_CTRL_PULSE_MS));
    return gpio_ctrl_set_level_checked(MNIST_GPIO_APAGA, 0);
}

esp_err_t gpio_ctrl_pulse_classifica(void)
{
    esp_err_t err = gpio_ctrl_set_level_checked(MNIST_GPIO_CLASSIFICA, 1);
    if (err != ESP_OK) {
        return err;
    }
    vTaskDelay(pdMS_TO_TICKS(MNIST_CTRL_PULSE_MS));
    return gpio_ctrl_set_level_checked(MNIST_GPIO_CLASSIFICA, 0);
}

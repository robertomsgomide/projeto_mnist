# -----------------------------------------------------------------------------
# mnist_top.sdc
# Constraints de timing para o projeto MNIST na DE0-CV.
# Clock principal: CLOCK_50 da placa, 50 MHz, periodo de 20 ns.
# -----------------------------------------------------------------------------

# Clock externo de 50 MHz da DE0-CV.
create_clock -name clock_50 -period 20.000 [get_ports {clock_50}]

# Incerteza de clock recomendada pelo TimeQuest para a familia/dispositivo.
derive_clock_uncertainty

# -----------------------------------------------------------------------------
# Entradas vindas da ESP32-S3
# -----------------------------------------------------------------------------
# escreve/apaga/classifica sao sinais logicos externos e assincronos.
# uart_rx_serial tambem e assincrono em relacao ao clock_50, embora seja
# amostrado internamente pelo receptor UART.
#
# O VHDL sincroniza esses sinais antes de usa-los no dominio clock_50.
# Por isso, a relacao temporal do pino externo ate o primeiro registrador de
# sincronizacao nao deve ser usada como criterio de setup/hold sincrono.
set_false_path -from [get_ports {escreve}]
set_false_path -from [get_ports {apaga}]
set_false_path -from [get_ports {classifica}]
set_false_path -from [get_ports {uart_rx_serial}]

# -----------------------------------------------------------------------------
# Observacao sobre VGA
# -----------------------------------------------------------------------------
# Nao criar clock separado para pixel_tick_25: no VHDL atual ele e usado como
# enable/tick de pixel dentro do dominio clock_50, nao como clock independente.
# -----------------------------------------------------------------------------

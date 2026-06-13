# WINDOWS
# Apenas um script conveniente para compilar todos os arquivos .vhd em ordem e rodar os testbenches

$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$ModelsimIni = "modelsim/modelsim.ini"
$TranscriptPath = "modelsim/transcript"
$WorkDir = "modelsim/work"

Set-Location -LiteralPath $ProjectRoot

if (Test-Path -LiteralPath $WorkDir) {
    Remove-Item -Recurse -Force -LiteralPath $WorkDir
}

vlib $WorkDir
vmap -modelsimini $ModelsimIni work $WorkDir

$files = @(
    "VHDL\mnist_tipos_pkg.vhd",
    "VHDL\mascaras_top64_pkg.vhd",
    "VHDL\bias_densos_pkg.vhd",
    "VHDL\font_5x7_pkg.vhd",
    "VHDL\testbenches\tb_uart_mnist_pkg.vhd",
    "VHDL\sincronizador_sinais.vhd",
    "VHDL\detector_borda.vhd",
    "VHDL\contador_pixel.vhd",
    "VHDL\acumuladores_digitos.vhd",
    "VHDL\argmax10.vhd",
    "VHDL\argmax10_signed.vhd",
    "VHDL\pontuador_top64_digit.vhd",
    "VHDL\classificador_binario_top64.vhd",
    "VHDL\rom_pesos_densos.vhd",
    "VHDL\classificador_denso_seq.vhd",
    "VHDL\reg_resultados.vhd",
    "VHDL\display7seg.vhd",
    "VHDL\display7seg_ctrl.vhd",
    "VHDL\leds_ctrl.vhd",
    "VHDL\uart_rx.vhd",
    "VHDL\uart_tx.vhd",
    "VHDL\uart_packet_rx.vhd",
    "VHDL\uart_packet_tx_ack.vhd",
    "VHDL\uart_frame_buffer.vhd",
    "VHDL\uart_frontend.vhd",
    "VHDL\mnist_canvas.vhd",
    "VHDL\mnist_uc.vhd",
    "VHDL\mnist_fd.vhd",
    "VHDL\interface_entrada.vhd",
    "VHDL\interface_saida.vhd",
    "VHDL\divisor_clock_25mhz.vhd",
    "VHDL\vga_sync_640x480.vhd",
    "VHDL\vga_render_mnist.vhd",
    "VHDL\vga_render_layout.vhd",
    "VHDL\vga_render_fonts.vhd",
    "VHDL\vga_top.vhd",
    "VHDL\mnist_top.vhd",
    "VHDL\testbenches\tb_uart_packet_rx.vhd",
    "VHDL\testbenches\tb_uart_frame_buffer.vhd",
    "VHDL\testbenches\tb_uart_frontend.vhd",
    "VHDL\testbenches\tb_mnist_canvas.vhd",
    "VHDL\testbenches\tb_interface_entrada.vhd",
    "VHDL\testbenches\tb_mnist_uc.vhd",
    "VHDL\testbenches\tb_mnist_top.vhd"
)

vcom -modelsimini $ModelsimIni -2008 -explicit -work work $files

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$testbenches = @(
    "tb_uart_packet_rx",
    "tb_uart_frame_buffer",
    "tb_uart_frontend",
    "tb_mnist_canvas",
    "tb_interface_entrada",
    "tb_mnist_uc",
    "tb_mnist_top"
)

foreach ($tb in $testbenches) {
    vsim -modelsimini $ModelsimIni -c -l $TranscriptPath -do "run -all; quit -f" "work.$tb"

    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

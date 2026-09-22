# Classificador MNIST em FPGA com Entrada Dinamica via UART

<div align="center">
  <img src="https://github.com/user-attachments/assets/f9b5f64c-d7d4-4faa-b39c-f9441422f909" alt="bancada_demo" width="600">
  <p><em>Foto registada em bancada</em></p>
</div>


Projeto em VHDL para classificar digitos manuscritos no formato MNIST usando a
FPGA **DE0-CV** (Cyclone V). A entrada vem de uma GUI Python no PC, passa por
uma ponte ESP32-S3 e chega a FPGA como frames 28x28 compactados via UART. A
imagem oficial classificada fica no canvas interno da FPGA, implementado em
`mnist_canvas.vhd`.

Fluxo principal:

```text
Wacom/mouse no PC Windows
    -> esp32/host/mnist_gui.py
    -> ESP32-S3 com firmware em esp32/bridge
    -> FPGA DE0-CV via GPIO/UART
    -> mnist_canvas.vhd
    -> classificadores MNIST + VGA/HEX/LED
```

A ESP32-S3 nao interpreta a mesa digitalizadora e nao classifica a imagem. O PC
recebe eventos normais de mouse/caneta, desenha no canvas, normaliza para 28x28,
binariza a imagem e envia 98 bytes de payload para a ponte.

Ferramentas usadas no desenvolvimento:

```text
Quartus Prime Lite 20.1.1   -> sintese e gravacao na DE0-CV
ModelSim                    -> simulacao dos testbenches (VHDL-2008)
ESP-IDF v6.0.1              -> firmware da ponte ESP32-S3
Python 3 + requirements.txt -> GUIs e scripts de apoio
```

## Responsabilidades

### PC e GUI Python

`esp32/host/mnist_gui.py` usa PySide6 e pyserial para listar portas COM,
conectar na ESP32-S3, desenhar o digito, mostrar o preview 28x28 e enviar o
comando `FC` para gravar o frame e pedir classificacao. A GUI abre mesmo sem
hardware conectado; nesse caso, comandos seriais registram erro no log e o
canvas continua utilizavel.

`python/fpga_sim.py` e uma GUI de simulacao semi-dinamica. Ela nao depende da
ESP32-S3: registra a sessao de desenho, salva snapshots do frame 28x28 e grava
um `session.json` que serve de entrada para `python/monta_tb.py` gerar um
testbench VHDL observacional (ver "Simulacao Python e testbench").

### ESP32-S3

`esp32/bridge` e um projeto ESP-IDF em C. Ele recebe comandos textuais pela
serial do PC, controla os sinais `escreve`, `apaga` e `classifica`, encaminha
frames compactados para a FPGA e valida ACK/NACK retornado pela UART da FPGA.

As configuracoes editaveis ficam em
`esp32/bridge/main/mnist_bridge_config.h`. Os GPIOs definidos ali sao defaults
plausiveis; confira a pinagem real da placa antes de ligar fisicamente
(`esp32/esp32_s3_pinout.jpg` traz a pinagem de referencia da placa usada). O
`sdkconfig` do projeto e versionado de proposito, para registrar a configuracao
ESP-IDF exata usada na entrega.

O uso de `UART_NUM_0` para PC <-> ESP32 funciona em placas com conversor
USB-UART ligado a UART0. Em placas com USB Serial/JTAG ou CDC nativo, pode ser
necessario adaptar o canal serial ou a configuracao ESP-IDF.

### FPGA DE0-CV

A FPGA recebe pacotes UART, valida estrutura/checksum, transforma payloads
validos em frames 28x28 e decide se altera o canvas conforme os controles
logicos ativos em alto:

```text
escreve    -> habilita escrita no canvas
apaga      -> limpa canvas/resultados na borda de subida
classifica -> solicita classificacao na borda de subida
```

`mnist_canvas.vhd` e dono da imagem oficial. Frames aceitos substituem a imagem
inteira quando `escreve = '1'`; com `escreve = '0'`, pacotes validos nao mudam o
conteudo salvo. `apaga` nao e reset global do sistema.

## Estrutura de arquivos

```text
projeto_mnist/
|-- README.md
|-- requirements.txt          dependencias Python (ver comentarios no arquivo)
|-- .gitignore
|-- VHDL/
|   `-- testbenches/
|-- python/
|   `-- sim_logs/             sessao exemplo gravada pela fpga_sim.py
|-- esp32/
|   |-- bridge/               firmware ESP-IDF da ponte
|   |-- host/                 GUI usada no fluxo real de hardware
|   `-- esp32_s3_pinout.jpg   pinagem de referencia da placa ESP32-S3
|-- quartus/                  projeto Quartus + bitstream pronto (.sof)
`-- modelsim/                 script de compilacao/execucao dos testbenches
```

### `VHDL/`

Contem o hardware do classificador: topo `mnist_top.vhd`, pacotes globais,
frontend UART, canvas MNIST, unidade de controle, fluxo de dados dos
classificadores, saidas VGA/LED/HEX e testbenches.

Blocos principais:

```text
mnist_top
|-- interface_entrada
|-- uart_frontend
|   |-- uart_rx / uart_tx
|   |-- uart_packet_rx / uart_packet_tx_ack
|   `-- uart_frame_buffer
|-- mnist_canvas
|-- mnist_uc
|-- mnist_fd
|   |-- classificador_binario_top64
|   `-- classificador_denso_seq
|-- interface_saida
`-- vga_top
```

Tres arquivos VHDL sao gerados por `python/gerar_pesos.py` e ja estao
incluidos prontos:

```text
rom_pesos_densos.vhd
bias_densos_pkg.vhd
mascaras_top64_pkg.vhd
```

O testbench `VHDL/testbenches/tb_mnist_top.vhd` tambem e gerado, mas por outro
caminho: `python/monta_tb.py` o produz a partir de uma sessao de desenho
gravada pela GUI `python/fpga_sim.py`. A versao entregue corresponde a sessao
`python/sim_logs/session_20260612_135332/session.json`, incluida no pacote para
permitir a repeticao dos mesmos estimulos. Os demais testbenches sao escritos a
mao.

### `python/`

Ferramentas de apoio. O arquivo `pesos_quantizados_info.txt` documenta os pesos
gerados.

```text
fpga_sim.py         -> GUI de simulacao; grava session.json + snapshots em
                       python/sim_logs/
monta_tb.py         -> le um session.json e gera o testbench observacional
                       tb_mnist_top.vhd
vga_build.py        -> converte vga_log.txt da simulacao VGA em PNGs 640x480
gui_layout.py       -> modulo compartilhado de layout/pre-processamento das GUIs
gerar_pesos.py      -> treina/quantiza os classificadores e gera os tres .vhd
                       de pesos; com --salvar-modelo, salva tambem
                       classificador_denso.keras e classificador_binario.npy
trace_benchmark.py  -> GUI para comparar, em software, os classificadores
                       binario/denso com a referencia CNN (sota_mnist.keras)
sota_mnist_gen.py   -> treina e salva a CNN Keras de referencia
                       (sota_mnist.keras e sota_mnist_stats.txt)
```

Os scripts de ML (`gerar_pesos.py`, `sota_mnist_gen.py`, `trace_benchmark.py`)
avaliam o comportamento dos classificadores modelados em software; eles nao
fazem parte do caminho de hardware sintetizado.

### `esp32/bridge`

Firmware ESP-IDF da ponte PC <-> FPGA. Implementa o protocolo textual do PC, a
UART binaria para a FPGA e o controle dos GPIOs `escreve`, `apaga` e
`classifica`.

### `esp32/host`

GUI Python usada no fluxo real de hardware. Precisa apenas de PySide6 e
pyserial (TensorFlow do `requirements.txt` so e necessario para os scripts de
ML em `python/`).

### `quartus/`

Arquivos do projeto Quartus da DE0-CV:

```text
mnist_top.qsf  -> assignments: lista de fontes VHDL e pinagem da DE0-CV
mnist_top.sdc  -> constraints de timing
mnist_top.qar  -> archive Quartus do projeto (backup autocontido)
output_files/mnist_top.sof -> bitstream pronto para gravar na placa
```

O `.sof` entregue permite gravar a DE0-CV sem recompilar nada.

### `modelsim/`

`quick_tb_mnist_test.ps1` compila todas as fontes em VHDL-2008 e executa os
sete testbenches em lote (ver "Uso rapido"). Os artefatos `work/`, `transcript`
e `modelsim.ini` sao gerados na execucao e nao acompanham a entrega.

## Uso rapido

### Sintese e gravacao na FPGA (Quartus)

Caminho rapido, sem recompilar: abra o Programmer do Quartus, conecte a DE0-CV
via USB-Blaster e grave `quartus/output_files/mnist_top.sof`.

Para recompilar o projeto:

1. No Quartus, acesse Project -> Restore Archived Project.
2. Selecione quartus/mnist_top.qar.
3. Escolha um diretorio de destino e restaure o projeto.
4. Abra o projeto restaurado.
5. Execute Processing -> Start Compilation.

A entidade de topo e `mnist_top` e toda a pinagem ja esta no `mnist_top.qsf`.

### Simulacao ModelSim

No PowerShell, com `vlib/vcom/vsim` no PATH:

```powershell
cd modelsim
.\quick_tb_mnist_test.ps1
```

O script recria a biblioteca `work`, compila todas as fontes de `VHDL/` em
VHDL-2008 e roda em sequencia os testbenches:

```text
tb_uart_packet_rx
tb_uart_frame_buffer
tb_uart_frontend
tb_mnist_canvas
tb_interface_entrada
tb_mnist_uc
tb_mnist_top
```

### Simulacao Python e geracao do tb_mnist_top

O `tb_mnist_top.vhd` e gerado em duas etapas: primeiro a GUI `fpga_sim.py`
grava uma sessao de desenho; depois o `monta_tb.py` converte essa sessao em
testbench.

Rode a GUI de simulacao:

```powershell
python python/fpga_sim.py
```

Fluxo recomendado:

```text
1. Clique em INICIAR.
2. Ligue ESCREVE.
3. Desenhe com mouse ou Wacom.
4. Clique em CLASSIFICAR.
5. Clique em ENCERRAR.
```

Ao encerrar, a sessao fica em `python/sim_logs/session_YYYYMMDD_HHMMSS/`
(`session.json` + snapshots do frame 28x28). Gere o testbench:

```powershell
python python/monta_tb.py python/sim_logs/session_YYYYMMDD_HHMMSS/session.json --out VHDL/testbenches/tb_mnist_top.vhd
```

Para tambem instanciar `vga_top` e registrar snapshots completos da GUI VGA,
adicione `--with-vga`:

```powershell
python python/monta_tb.py python/sim_logs/session_YYYYMMDD_HHMMSS/session.json --out VHDL/testbenches/tb_mnist_top.vhd --with-vga
```

O testbench gerado envia os estimulos do JSON, reporta transicoes relevantes
de UART, controles, canvas e classificacao, e grava `vga_log.txt` na pasta da
sessao. Divergencias aparecem como `warning`, sem `assert failure` automatico.

Depois de rodar o testbench no ModelSim, converta o log VGA para PNG:

```powershell
python python/vga_build.py python/sim_logs/session_YYYYMMDD_HHMMSS
```

Tambem e possivel passar o arquivo diretamente:

```powershell
python python/vga_build.py python/sim_logs/session_YYYYMMDD_HHMMSS/vga_log.txt
```

O conversor cria automaticamente
`python/sim_logs/session_YYYYMMDD_HHMMSS/vga_snapshots/` e salva imagens como
`vga_classifica_evt0008.png` e `vga_apaga_evt0009.png`.

O `tb_mnist_top.vhd` entregue corresponde a sessao exemplo
`python/sim_logs/session_20260612_135332`. O comando acima regenera um testbench
funcionalmente equivalente, com os mesmos estimulos e verificacoes. O horario
de geracao e os caminhos exibidos apenas em mensagens de diagnostico podem
variar conforme o computador e o diretorio em que o projeto for executado.

### Regeneracao dos pesos (opcional)

Os tres arquivos VHDL de parametros ja estao prontos em `VHDL/`:

```text
rom_pesos_densos.vhd
bias_densos_pkg.vhd
mascaras_top64_pkg.vhd
```

Para treinar novamente os classificadores com a configuracao principal usada
na versao final e sobrescrever esses arquivos:

```powershell
python python/gerar_pesos.py `
  --saida-dir VHDL `
  --salvar-modelo `
  --epochs 25 `
  --batch-size 128 `
  --validation-split 0.20 `
  --threshold 0.30 `
  --seed 42 `
  --early-stop `
  --augmented `
  --aug-factor 2 `
  --aug-seed 42 `
  --aug-profile leve
```

O `--early-stop` pode encerrar o treinamento antes das 25 epocas solicitadas.
Com `--salvar-modelo`, o script tambem salva em `python/` os artefatos usados
pelo benchmark em software: `classificador_denso.keras` e
`classificador_binario.npy`.

A execucao requer NumPy e TensorFlow. Pequenas diferencas numericas podem
ocorrer entre versoes das bibliotecas, sistemas operacionais e dispositivos de
calculo; portanto, uma nova execucao nao e necessariamente identica byte a byte
aos artefatos entregues. Os parametros efetivamente incorporados ao hardware e
as metricas obtidas na geracao final estao documentados em
`python/pesos_quantizados_info.txt`.

### Firmware ESP32-S3

```bash
cd esp32/bridge
idf.py set-target esp32s3
idf.py build
idf.py flash monitor
```

O `sdkconfig` versionado ja contem a configuracao usada (ESP-IDF v6.0.1).

### GUI host para hardware

Para usar somente a GUI de hardware, instale apenas suas duas dependencias:

```bash
python -m pip install PySide6 pyserial
python esp32/host/mnist_gui.py
```

Para executar tambem os scripts de treinamento e benchmark em `python/`,
instale o conjunto completo:

```bash
python -m pip install -r requirements.txt
```

Conecte a ESP32-S3 ao PC, selecione a porta COM, mantenha o baud rate em
`1000000` salvo se o firmware tambem for alterado, clique em `CONECTAR` e use
`PING` para testar a comunicacao.

No fluxo normal, desenhe o digito e clique em `CLASSIFICAR`. A GUI envia:

```text
FC <seq_hex_2_digitos> <payload_hex_196_digitos>
```

`FC` faz a ESP32-S3 habilitar `escreve`, encaminhar o frame para a FPGA,
aguardar ACK/NACK e, em seguida, desabilitar `escreve` independentemente do
resultado. O pulso `classifica` so e emitido quando a FPGA responde com ACK.
`APAGAR` envia `A` e limpa o canvas local. `ESCREVE` envia `E 1` ou `E 0`
manualmente para diagnostico; nao e necessario no fluxo normal de
classificacao.

## Protocolos

### PC -> ESP32-S3

O protocolo textual usa uma linha por comando, terminada por `\n` ou `\r\n`.
Espacos extras sao ignorados.

```text
PING
STATUS
E 0
E 1
A
C
F  <seq_hex_2_digitos> <payload_hex_196_digitos>
FC <seq_hex_2_digitos> <payload_hex_196_digitos>
```

Respostas seguem o formato `OK ...`, `ERR ...` ou `LOG ...`. Exemplos:

```text
OK PONG
OK F 03 ACK
OK FC 04 ACK CLASSIFICA
ERR F 05 NACK 04
ERR F 06 TIMEOUT
ERR BAD_CMD
ERR BAD_HEX
ERR BAD_LEN
```

Em erro, a ponte retorna `escreve = 0` por seguranca e nao pulsa `classifica`.

### ESP32-S3 -> FPGA

O frame MNIST usa o protocolo binario da FPGA:

```text
HEADER  = A5 5A
CMD     = 01
LEN     = 62 00
SEQ     = 1 byte
PAYLOAD = 98 bytes
CHK     = XOR de CMD, LEN_L, LEN_H, SEQ e payload
```

Cada bit representa um pixel 28x28 em ordem row-major:

```text
PAYLOAD[0] bit 7 -> pixel 0
PAYLOAD[0] bit 6 -> pixel 1
...
PAYLOAD[97] bit 0 -> pixel 783
```

Como a imagem tem 784 pixels, o frame binarizado ocupa `784 / 8 = 98` bytes. Um
bit `0` representa pixel apagado; um bit `1`, pixel aceso.

A FPGA responde:

```text
HEADER  = A5 5A
CMD     = 06 para ACK, 15 para NACK
LEN     = 01 00
SEQ     = sequencia recebida
PAYLOAD = 1 byte de erro, zero no ACK
CHK     = XOR de CMD, LEN_L, LEN_H, SEQ e erro
```

Pacotes incompletos, com tamanho incorreto ou checksum invalido nao devem
alterar o canvas.

## Ligacao fisica

Ligacao conceitual minima:

```text
ESP32-S3 TX   -> FPGA UART RX
ESP32-S3 RX   <- FPGA UART TX
ESP32-S3 GPIO -> FPGA escreve/apaga/classifica
ESP32-S3 GND  <-> FPGA GND
```

Com a configuracao entregue em `mnist_bridge_config.h`, o mapeamento do lado
ESP32-S3 e:

```text
GPIO 17 -> FPGA UART RX
GPIO 18 <- FPGA UART TX
GPIO 4  -> escreve
GPIO 5  -> apaga
GPIO 6  -> classifica
```

GND da ESP32-S3 e GND da DE0-CV precisam estar em comum. Os sinais esperados
pela FPGA sao 3.3 V. A pinagem de referencia da placa ESP32-S3 usada esta em
`esp32/esp32_s3_pinout.jpg`; os GPIOs do lado ESP32 sao definidos em
`esp32/bridge/main/mnist_bridge_config.h`.

O lado FPGA esta mapeado no `quartus/mnist_top.qsf` para GPIO_0 da DE0-CV:

```text
GPIO_0_D0 -> escreve
GPIO_0_D1 -> apaga
GPIO_0_D2 -> classifica
GPIO_0_D3 -> uart_rx_serial
GPIO_0_D4 -> uart_tx_serial
```

## Classificadores e saidas

O classificador binario top-64 e combinacional: para cada classe, conta pixels
relevantes ativos e escolhe o digito com maior pontuacao. Sua acuracia medida
no conjunto de teste MNIST original foi de 71,03%.

O classificador denso sequencial usa uma camada densa quantizada: percorre os
784 pixels e, quando um pixel esta ativo, soma os pesos correspondentes aos dez
acumuladores. Sua acuracia medida no conjunto de teste MNIST original foi de
91,79%. Entre a aceitacao do inicio e a ativacao de `denso_pronto`, a inferencia
consome 796 ciclos do clock de 50 MHz, equivalentes a aproximadamente 15,92 us.

Os numeros detalhados de treino, teste MNIST original e teste com augmentation
estao em `python/pesos_quantizados_info.txt`.

A VGA exibe a imagem atual do canvas, estado de escrita, validade da imagem,
status da UART, status de classificacao, predicoes e indicacao de erro. LEDs e
displays HEX sao usados para diagnostico em bancada.

## Observacoes de implementacao

A entidade de topo esperada para sintese e `mnist_top`. Portas logicas
principais:

```text
clock_50
escreve
apaga
classifica
uart_rx_serial
uart_tx_serial
ledr
hex0..hex5
vga_r/vga_g/vga_b/vga_hs/vga_vs
```

A maior parte do sistema opera no clock principal de 50 MHz da DE0-CV. A VGA usa
um pulso de habilitacao de pixel em 25 MHz gerado por `divisor_clock_25mhz.vhd`.
As UARTs devem ser parametrizadas de forma consistente com a frequencia de
clock e o baud rate. Na configuracao entregue, tanto o enlace PC <-> ESP32-S3
quanto o enlace ESP32-S3 <-> FPGA operam a 1.000.000 baud.

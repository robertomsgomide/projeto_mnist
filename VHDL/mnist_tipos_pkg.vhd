-------------------------------------------------------------------------------
-- Arquivo   : mnist_tipos_pkg.vhd
-------------------------------------------------------------------------------
-- Descricao : pacote com tipos, subtipos e constantes globais do projeto MNIST.
--             Define a representacao da imagem 28x28, tipos de digitos,
--             vetores de scores, larguras de sinais e estruturas auxiliares
--             compartilhadas pelos classificadores e interfaces do sistema.
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     18/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  versao inicial
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package mnist_tipos_pkg is

    --------------------------------------------------------------------
    -- Clock e tempos globais
    --------------------------------------------------------------------
    constant CLOCK_FREQ_HZ_C : natural := 50_000_000;
    constant UART_BAUD_C     : natural := 1_000_000;

    --------------------------------------------------------------------
    -- Recursos de saida da DE0-CV usados pelo projeto
    --------------------------------------------------------------------
    constant LED_COUNT_C : natural := 10;

    subtype led_bus_t is std_logic_vector(LED_COUNT_C-1 downto 0);

    --------------------------------------------------------------------
    -- Displays HEX
    --------------------------------------------------------------------
    subtype hex7seg_t      is std_logic_vector(6 downto 0);
    subtype hex_codigo_t   is std_logic_vector(4 downto 0);

    constant HEX_COD_0_C     : hex_codigo_t := "00000";
    constant HEX_COD_1_C     : hex_codigo_t := "00001";
    constant HEX_COD_2_C     : hex_codigo_t := "00010";
    constant HEX_COD_3_C     : hex_codigo_t := "00011";
    constant HEX_COD_4_C     : hex_codigo_t := "00100";
    constant HEX_COD_5_C     : hex_codigo_t := "00101";
    constant HEX_COD_6_C     : hex_codigo_t := "00110";
    constant HEX_COD_7_C     : hex_codigo_t := "00111";
    constant HEX_COD_8_C     : hex_codigo_t := "01000";
    constant HEX_COD_9_C     : hex_codigo_t := "01001";
    constant HEX_COD_E_C     : hex_codigo_t := "01110";
    constant HEX_COD_BLANK_C : hex_codigo_t := "11111";

    --------------------------------------------------------------------
    -- Imagem MNIST
    --------------------------------------------------------------------
    constant IMG_WIDTH_C  : natural := 28;
    constant IMG_HEIGHT_C : natural := 28;
    constant IMG_BITS_C   : natural := IMG_WIDTH_C * IMG_HEIGHT_C;

    constant PIXEL_ADDR_WIDTH_C : natural := 10;

    subtype imagem_mnist_t is std_logic_vector(IMG_BITS_C-1 downto 0);
    subtype pixel_addr_t   is unsigned(PIXEL_ADDR_WIDTH_C-1 downto 0);
    subtype pixel_index_t  is natural range 0 to IMG_BITS_C-1;

    --------------------------------------------------------------------
    -- Classificadores
    --------------------------------------------------------------------
    constant NUM_DIGITOS_C : natural := 10;

    subtype digito_t is unsigned(3 downto 0);

    --------------------------------------------------------------------
    -- Classificador binário top-64
    --------------------------------------------------------------------
    constant TOP_K_C           : natural := 64;
    constant SCORE_BIN_WIDTH_C : natural := 7;

    subtype score_bin_t is unsigned(SCORE_BIN_WIDTH_C-1 downto 0);

    type score_bin_array_t is array (0 to NUM_DIGITOS_C-1) of score_bin_t;

    subtype indice_pixel_t is natural range 0 to IMG_BITS_C-1;

    type indices_top64_t       is array (0 to TOP_K_C-1) of indice_pixel_t;
    type indices_top64_array_t is array (0 to NUM_DIGITOS_C-1) of indices_top64_t;

    --------------------------------------------------------------------
    -- Classificador denso
    --------------------------------------------------------------------
    constant PESO_WIDTH_C        : natural := 8;
    constant SCORE_DENSO_WIDTH_C : natural := 20;

    subtype peso_t        is signed(PESO_WIDTH_C-1 downto 0);
    subtype score_denso_t is signed(SCORE_DENSO_WIDTH_C-1 downto 0);

    type peso10_array_t      is array (0 to NUM_DIGITOS_C-1) of peso_t;
    type score_denso_array_t is array (0 to NUM_DIGITOS_C-1) of score_denso_t;

    --------------------------------------------------------------------
    -- UART
    --------------------------------------------------------------------
    subtype uart_byte_t is std_logic_vector(7 downto 0);
    subtype uart_seq_t  is std_logic_vector(7 downto 0);

    constant UART_HEADER0_C : uart_byte_t := x"A5";
    constant UART_HEADER1_C : uart_byte_t := x"5A";

    constant UART_CMD_FRAME_C : uart_byte_t := x"01";
    constant UART_CMD_ACK_C   : uart_byte_t := x"06";
    constant UART_CMD_NACK_C  : uart_byte_t := x"15";

    constant UART_PAYLOAD_FRAME_BYTES_C : natural := IMG_BITS_C / 8;
    constant UART_PAYLOAD_INDEX_WIDTH_C : natural := 7;

    subtype uart_len_t           is unsigned(15 downto 0);
    subtype uart_payload_index_t is unsigned(UART_PAYLOAD_INDEX_WIDTH_C-1 downto 0);

    subtype uart_erro_t is std_logic_vector(3 downto 0);

    constant UART_ERRO_NENHUM_C      : uart_erro_t := x"0";
    constant UART_ERRO_HEADER_C      : uart_erro_t := x"1";
    constant UART_ERRO_COMANDO_C     : uart_erro_t := x"2";
    constant UART_ERRO_TAMANHO_C     : uart_erro_t := x"3";
    constant UART_ERRO_CHECKSUM_C    : uart_erro_t := x"4";
    constant UART_ERRO_FRAME_C       : uart_erro_t := x"5";

    --------------------------------------------------------------------
    -- Unidade de controle
    --------------------------------------------------------------------
    subtype estado_uc_t is std_logic_vector(2 downto 0);

    constant UC_IDLE_C        : estado_uc_t := "000";
    constant UC_CLASSIFICA_C  : estado_uc_t := "001";
    constant UC_AGUARDA_C     : estado_uc_t := "010";
    constant UC_REGISTRA_C    : estado_uc_t := "011";
    constant UC_PRONTO_C      : estado_uc_t := "100";

    --------------------------------------------------------------------
    -- VGA
    --------------------------------------------------------------------
    constant VGA_COORD_BITS_C : natural := 10;
    constant VGA_COORD_MAX_C  : natural := 2**VGA_COORD_BITS_C - 1;

    subtype vga_coord_t     is unsigned(VGA_COORD_BITS_C-1 downto 0);
    subtype vga_coord_int_t is natural range 0 to VGA_COORD_MAX_C;

    subtype vga_cor_t is std_logic_vector(11 downto 0);

    constant VGA_PRETO_C    : vga_cor_t := x"000";
    constant VGA_BRANCO_C   : vga_cor_t := x"FFF";
    constant VGA_CINZA_C    : vga_cor_t := x"888";
    constant VGA_VERDE_C    : vga_cor_t := x"0F0";
    constant VGA_VERMELHO_C : vga_cor_t := x"F00";
    constant VGA_AZUL_C     : vga_cor_t := x"00F";

    constant VGA_H_VISIBLE_C : natural := 640;
    constant VGA_H_FP_C      : natural := 16;
    constant VGA_H_SYNC_C    : natural := 96;
    constant VGA_H_BP_C      : natural := 48;
    constant VGA_H_TOTAL_C   : natural := VGA_H_VISIBLE_C + VGA_H_FP_C + VGA_H_SYNC_C + VGA_H_BP_C;

    constant VGA_V_VISIBLE_C : natural := 480;
    constant VGA_V_FP_C      : natural := 10;
    constant VGA_V_SYNC_C    : natural := 2;
    constant VGA_V_BP_C      : natural := 33;
    constant VGA_V_TOTAL_C   : natural := VGA_V_VISIBLE_C + VGA_V_FP_C + VGA_V_SYNC_C + VGA_V_BP_C;

    constant VGA_MNIST_X_C     : natural := 46;
    constant VGA_MNIST_Y_C     : natural := 142;
    constant VGA_MNIST_SCALE_C : natural := 8;

    constant VGA_MNIST_W_C : natural := IMG_WIDTH_C  * VGA_MNIST_SCALE_C;
    constant VGA_MNIST_H_C : natural := IMG_HEIGHT_C * VGA_MNIST_SCALE_C;

end package mnist_tipos_pkg;

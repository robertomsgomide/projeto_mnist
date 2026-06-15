-------------------------------------------------------------------------------
-- Arquivo   : interface_saida.vhd
-------------------------------------------------------------------------------
-- Descricao : concentra a interface de saida do sistema. Distribui sinais de
--             interacao para LEDs e resultados, estados e codigos de erro para
--             displays de 7 segmentos.
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     18/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  versao inicial
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;

entity interface_saida is
    port (
        clock : in std_logic;
        reset : in std_logic;

        limpa_canvas_pulso : in std_logic;

        escrita_habilitada : in std_logic;
        imagem_valida      : in std_logic;

        uart_recebendo    : in std_logic;
        pacote_ok_pulso   : in std_logic;
        pacote_erro_pulso : in std_logic;
        erro_codigo       : in uart_erro_t;

        classificacao_ocupada : in std_logic;
        resultado_valido      : in std_logic;
        classificadores_concordam : in std_logic;

        digito_binario : in digito_t;
        digito_denso   : in digito_t;

        estado_uc : in estado_uc_t;

        ledr : out led_bus_t;

        hex0 : out hex7seg_t;
        hex1 : out hex7seg_t;
        hex2 : out hex7seg_t;
        hex3 : out hex7seg_t;
        hex4 : out hex7seg_t;
        hex5 : out hex7seg_t
    );
end entity interface_saida;

architecture estrutural of interface_saida is

    component leds_ctrl is
        generic (
            CICLO_LED_TICKS_G : positive := CLOCK_FREQ_HZ_C / 10;
            FLASH_LED_TICKS_G : positive := CLOCK_FREQ_HZ_C / 2
        );
        port (
            clock : in std_logic;
            reset : in std_logic;

            limpa_canvas_pulso : in std_logic;

            aguarda : in std_logic;

            ledr : out led_bus_t
        );
    end component;

    component display7seg_ctrl is
        port (
            escrita_habilitada : in std_logic;
            resultado_valido : in std_logic;

            classificacao_ocupada : in std_logic;
            erro_codigo           : in uart_erro_t;

            digito_binario : in digito_t;
            digito_denso   : in digito_t;

            hex0_codigo : out hex_codigo_t;
            hex1_codigo : out hex_codigo_t;
            hex2_codigo : out hex_codigo_t;
            hex3_codigo : out hex_codigo_t;
            hex4_codigo : out hex_codigo_t;
            hex5_codigo : out hex_codigo_t
        );
    end component;

    component display7seg is
        port (
            hex     : in  hex_codigo_t;
            display : out hex7seg_t
        );
    end component;

    signal hex0_codigo_s : hex_codigo_t := HEX_COD_BLANK_C;
    signal hex1_codigo_s : hex_codigo_t := HEX_COD_BLANK_C;
    signal hex2_codigo_s : hex_codigo_t := HEX_COD_BLANK_C;
    signal hex3_codigo_s : hex_codigo_t := HEX_COD_BLANK_C;
    signal hex4_codigo_s : hex_codigo_t := HEX_COD_BLANK_C;
    signal hex5_codigo_s : hex_codigo_t := HEX_COD_BLANK_C;
    signal aguarda_s     : std_logic := '0';

begin

    aguarda_s <= '1' when estado_uc = UC_IDLE_C else '0';

    u_leds_ctrl : leds_ctrl
        port map (
            clock                    => clock,
            reset                    => reset,
            limpa_canvas_pulso       => limpa_canvas_pulso,
            aguarda                  => aguarda_s,
            ledr                     => ledr
        );

    u_display7seg_ctrl : display7seg_ctrl
        port map (
            escrita_habilitada       => escrita_habilitada,
            resultado_valido         => resultado_valido,
            classificacao_ocupada    => classificacao_ocupada,
            erro_codigo              => erro_codigo,
            digito_binario           => digito_binario,
            digito_denso             => digito_denso,
            hex0_codigo              => hex0_codigo_s,
            hex1_codigo              => hex1_codigo_s,
            hex2_codigo              => hex2_codigo_s,
            hex3_codigo              => hex3_codigo_s,
            hex4_codigo              => hex4_codigo_s,
            hex5_codigo              => hex5_codigo_s
        );

    u_hex0 : display7seg
        port map (
            hex     => hex0_codigo_s,
            display => hex0
        );

    u_hex1 : display7seg
        port map (
            hex     => hex1_codigo_s,
            display => hex1
        );

    u_hex2 : display7seg
        port map (
            hex     => hex2_codigo_s,
            display => hex2
        );

    u_hex3 : display7seg
        port map (
            hex     => hex3_codigo_s,
            display => hex3
        );

    u_hex4 : display7seg
        port map (
            hex     => hex4_codigo_s,
            display => hex4
        );

    u_hex5 : display7seg
        port map (
            hex     => hex5_codigo_s,
            display => hex5
        );

end architecture estrutural;

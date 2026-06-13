-------------------------------------------------------------------------------
-- Arquivo   : display7seg_ctrl.vhd
-------------------------------------------------------------------------------
-- Descricao : controlador dos displays HEX. Seleciona quais predicoes e codigo
--             de erro sao apresentados nos displays de 7 segmentos.
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     18/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  versao inicial
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;

entity display7seg_ctrl is
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
end entity display7seg_ctrl;

architecture arch of display7seg_ctrl is

    function digito_para_hex(digito : digito_t) return hex_codigo_t is
    begin
        case to_integer(digito) is
            when 0 => return HEX_COD_0_C;
            when 1 => return HEX_COD_1_C;
            when 2 => return HEX_COD_2_C;
            when 3 => return HEX_COD_3_C;
            when 4 => return HEX_COD_4_C;
            when 5 => return HEX_COD_5_C;
            when 6 => return HEX_COD_6_C;
            when 7 => return HEX_COD_7_C;
            when 8 => return HEX_COD_8_C;
            when 9 => return HEX_COD_9_C;
            when others => return HEX_COD_BLANK_C;
        end case;
    end function;

    signal mostra_resultado_s : std_logic;

begin

    mostra_resultado_s <= '1' when
        escrita_habilitada = '0' and
        classificacao_ocupada = '0' and
        resultado_valido = '1'
        else '0';

    hex0_codigo <= HEX_COD_E_C when erro_codigo = UART_ERRO_HEADER_C else
                   digito_para_hex(digito_denso) when mostra_resultado_s = '1' else
                   HEX_COD_BLANK_C;

    hex1_codigo <= HEX_COD_E_C when erro_codigo = UART_ERRO_HEADER_C else
                   HEX_COD_BLANK_C;
    hex2_codigo <= HEX_COD_E_C when erro_codigo = UART_ERRO_HEADER_C else
                   HEX_COD_BLANK_C;
    hex3_codigo <= HEX_COD_E_C when erro_codigo = UART_ERRO_HEADER_C else
                   HEX_COD_BLANK_C;
    hex4_codigo <= HEX_COD_E_C when erro_codigo = UART_ERRO_HEADER_C else
                   HEX_COD_BLANK_C;

    hex5_codigo <= HEX_COD_E_C when erro_codigo = UART_ERRO_HEADER_C else
                   digito_para_hex(digito_binario) when mostra_resultado_s = '1' else
                   HEX_COD_BLANK_C;

end architecture arch;

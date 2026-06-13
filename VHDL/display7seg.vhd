-------------------------------------------------------------------------------
-- Arquivo   : display7seg.vhd (hex7seg.vhd adaptado)
-------------------------------------------------------------------------------
-- Descricao : Conversor para 7 segmentos ativo em baixo.
--
--             Codigos 0xxxx preservam o mapeamento hexadecimal original:
--             00000..01111 = 0..F.
--
--             Codigos 1xxxx acrescentam simbolos auxiliares usados pelos
--             modos de exibicao do classificador MNIST.
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                               Descricao
--     20/02/2026  1.0     Edson Midorikawa e Felipe Valencia  versao inicial
--     01/05/2026  1.1     Roberto M S Gomide / Rodrigo Haruna  simbolos auxiliares
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;

entity display7seg is
    port (
        hex     : in  hex_codigo_t;
        display : out hex7seg_t
    );
end entity display7seg;

architecture arch of display7seg is
begin
    display <= "1000000" when hex = HEX_COD_0_C else -- 0
               "1111001" when hex = HEX_COD_1_C else -- 1
               "0100100" when hex = HEX_COD_2_C else -- 2
               "0110000" when hex = HEX_COD_3_C else -- 3
               "0011001" when hex = HEX_COD_4_C else -- 4
               "0010010" when hex = HEX_COD_5_C else -- 5
               "0000010" when hex = HEX_COD_6_C else -- 6
               "1111000" when hex = HEX_COD_7_C else -- 7
               "0000000" when hex = HEX_COD_8_C else -- 8
               "0010000" when hex = HEX_COD_9_C else -- 9
               "0001000" when hex = "01010" else -- A
               "0000011" when hex = "01011" else -- b
               "1000110" when hex = "01100" else -- C
               "0100001" when hex = "01101" else -- d
               "0000110" when hex = HEX_COD_E_C else -- E
               "0001110" when hex = "01111" else -- F
               "0001100" when hex = "10001" else -- P
               "1111111";
end architecture arch;

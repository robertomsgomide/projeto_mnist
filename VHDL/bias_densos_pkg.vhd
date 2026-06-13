-------------------------------------------------------------------------------
-- Arquivo   : bias_densos_pkg.vhd
-- Descricao : Pacote de biases quantizados do classificador denso.
-- Parametros de geracao:
--   escala_quantizacao: 69.5469546118
-------------------------------------------------------------------------------
-- ATENCAO: arquivo gerado automaticamente por gerar_pesos.py.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;

package bias_densos_pkg is

    --------------------------------------------------------------------
    -- Biases quantizados com a mesma escala dos pesos int8.
    -- Escala de quantizacao: 69.5469546118
    --------------------------------------------------------------------
    constant BIAS_DENSOS_C : score_denso_array_t := (
        0 => to_signed(-43, SCORE_DENSO_WIDTH_C),
        1 => to_signed(41, SCORE_DENSO_WIDTH_C),
        2 => to_signed(17, SCORE_DENSO_WIDTH_C),
        3 => to_signed(-29, SCORE_DENSO_WIDTH_C),
        4 => to_signed(-1, SCORE_DENSO_WIDTH_C),
        5 => to_signed(101, SCORE_DENSO_WIDTH_C),
        6 => to_signed(-23, SCORE_DENSO_WIDTH_C),
        7 => to_signed(48, SCORE_DENSO_WIDTH_C),
        8 => to_signed(-98, SCORE_DENSO_WIDTH_C),
        9 => to_signed(-17, SCORE_DENSO_WIDTH_C)
    );

end package bias_densos_pkg;

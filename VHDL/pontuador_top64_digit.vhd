-------------------------------------------------------------------------------
-- Arquivo   : pontuador_top64_digit.vhd
-------------------------------------------------------------------------------
-- Descricao : calcula a pontuacao de um digito somando apenas os pixels
-- indicados pela lista top-64 correspondente. Esta versao evita popcount sobre
-- os 784 pixels completos.
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     18/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  versao inicial
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;
use work.mascaras_top64_pkg.all;

entity pontuador_top64_digit is
    generic (
        DIGITO_G : natural range 0 to NUM_DIGITOS_C-1 := 0
    );
    port (
        imagem : in imagem_mnist_t;
        score  : out score_bin_t
    );
end entity pontuador_top64_digit;

architecture arch of pontuador_top64_digit is
    constant INDICES_C : indices_top64_t := INDICES_TOP64_C(DIGITO_G);
begin
    process(imagem)
        variable soma : score_bin_t;
    begin
        soma := (others => '0');

        for k in 0 to TOP_K_C-1 loop
            if imagem(INDICES_C(k)) = '1' then
                soma := soma + 1;
            end if;
        end loop;

        score <= soma;
    end process;
end architecture arch;
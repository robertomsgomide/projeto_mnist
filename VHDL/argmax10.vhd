-------------------------------------------------------------------------------
-- Arquivo   : argmax10.vhd
-------------------------------------------------------------------------------
-- Descricao : recebe dez pontuacoes e devolve o indice do maior valor.
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     01/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  novo componente
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;

entity argmax10 is
    port (
        scores : in score_bin_array_t;

        digito_max : out digito_t;
        score_max  : out score_bin_t
    );
end entity argmax10;


architecture arch of argmax10 is
    begin
        process(scores)
            variable melhor_score : score_bin_t;
            variable melhor_idx   : integer range 0 to NUM_DIGITOS_C-1;
        begin
            melhor_score := scores(0);
            melhor_idx   := 0;
            for d in 1 to NUM_DIGITOS_C-1 loop
                if scores(d) > melhor_score then
                    melhor_score := scores(d);
                    melhor_idx   := d;
                end if;
            end loop;
            digito_max <= to_unsigned(melhor_idx, digito_t'length);
            score_max  <= melhor_score;
        end process;
    end architecture arch;
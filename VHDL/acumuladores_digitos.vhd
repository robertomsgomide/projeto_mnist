-------------------------------------------------------------------------------
-- Arquivo   : acumuladores_digitos.vhd
-------------------------------------------------------------------------------
-- Descricao : guarda dez acumuladores assinados de 20 bits.
-- Na limpeza de uma nova inferência, os acumuladores recebem os biases
-- quantizados do classificador denso.
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     18/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  novo componente
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;

entity acumuladores_digitos is
    port (
        clock : in std_logic;
        reset : in std_logic;

        limpa    : in std_logic;
        habilita : in std_logic;

        pixel_ativo : in std_logic;

        pesos  : in peso10_array_t;
        biases : in score_denso_array_t;

        scores : out score_denso_array_t
    );
end entity acumuladores_digitos;

architecture arch of acumuladores_digitos is
    signal acc : score_denso_array_t;
begin

    process(clock, reset)
    begin
        if reset = '1' then
            for d in 0 to NUM_DIGITOS_C-1 loop
                acc(d) <= (others => '0');
            end loop;
        elsif rising_edge(clock) then
            if limpa = '1' then
                for d in 0 to NUM_DIGITOS_C-1 loop
                    acc(d) <= biases(d);
                end loop;
            elsif habilita = '1' and pixel_ativo = '1' then
                for d in 0 to NUM_DIGITOS_C-1 loop
                    acc(d) <= acc(d) + resize(pesos(d), SCORE_DENSO_WIDTH_C);
                end loop;
            end if;
        end if;
    end process;

    scores <= acc;

end architecture arch;
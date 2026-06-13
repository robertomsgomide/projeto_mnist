-------------------------------------------------------------------------------
-- Arquivo   : classificador_binario_top64.vhd
-------------------------------------------------------------------------------
-- Descricao : classificador binário combinacional
-- para cada dígito, existe uma lista dos 64 pixels mais representativos;
-- o classificador conta quantos desses pixels estão ativos na imagem de entrada;
-- o dígito com maior contagem é escolhido;
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     01/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  novo componente
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;

entity classificador_binario_top64 is
    port (
        imagem : in imagem_mnist_t;

        scores : out score_bin_array_t;

        digito_saida : out digito_t;
        score_max    : out score_bin_t
    );
end entity classificador_binario_top64;

architecture arch of classificador_binario_top64 is
    signal scores_int : score_bin_array_t;
begin
    g_digitos : for d in 0 to NUM_DIGITOS_C-1 generate
        u_pont : entity work.pontuador_top64_digit
            generic map (
                DIGITO_G => d
            )
            port map (
                imagem => imagem,
                score  => scores_int(d)
            );
    end generate;

    u_argmax : entity work.argmax10
        port map (
            scores     => scores_int,
            digito_max => digito_saida,
            score_max  => score_max
        );

    scores <= scores_int;
end architecture arch;
-------------------------------------------------------------------------------
-- Arquivo   : mnist_fd.vhd
-------------------------------------------------------------------------------
-- Descricao : fluxo de dados do classificador MNIST com entrada dinamica.
--             Registra a imagem 28x28 recebida pela UART, alimenta os
--             classificadores binario e denso, e armazena as predicoes finais.
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     18/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  versao inicial
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;

entity mnist_fd is
    port (
        clock : in std_logic;
        reset : in std_logic;

        imagem : in imagem_mnist_t;

        inicia_denso       : in std_logic;
        registra_resultado : in std_logic;
        limpa_resultado    : in std_logic;

        denso_pronto : out std_logic;

        digito_binario : out digito_t;
        digito_denso   : out digito_t;

        resultado_valido : out std_logic;
        classificadores_concordam : out std_logic
    );
end entity mnist_fd;

architecture arch of mnist_fd is

    component classificador_binario_top64 is
        port (
            imagem : in imagem_mnist_t;

            scores : out score_bin_array_t;

            digito_saida : out digito_t;
            score_max    : out score_bin_t
        );
    end component;

    component classificador_denso_seq is
        port (
            clock : in std_logic;
            reset : in std_logic;

            iniciar : in std_logic;

            imagem : in imagem_mnist_t;

            pronto       : out std_logic;
            digito_saida : out digito_t
        );
    end component;

    component reg_resultados is
        port (
            clock : in std_logic;
            reset : in std_logic;

            limpa    : in std_logic;
            registra : in std_logic;

            digito_binario_in : in digito_t;
            digito_denso_in   : in digito_t;

            digito_binario_out : out digito_t;
            digito_denso_out   : out digito_t;

            resultado_valido : out std_logic;
            classificadores_concordam : out std_logic
        );
    end component;

    signal scores_binario_s : score_bin_array_t;
    signal score_bin_max_s  : score_bin_t := (others => '0');

    signal digito_binario_calc_s : digito_t := (others => '0');
    signal digito_denso_calc_s   : digito_t := (others => '0');

begin

    u_classificador_binario : classificador_binario_top64
        port map (
            imagem       => imagem,
            scores       => scores_binario_s,
            digito_saida => digito_binario_calc_s,
            score_max    => score_bin_max_s
        );

    u_classificador_denso : classificador_denso_seq
        port map (
            clock        => clock,
            reset        => reset,
            iniciar      => inicia_denso,
            imagem       => imagem,
            pronto       => denso_pronto,
            digito_saida => digito_denso_calc_s
        );

    u_reg_resultados : reg_resultados
        port map (
            clock                 => clock,
            reset                 => reset,
            limpa                 => limpa_resultado,
            registra              => registra_resultado,
            digito_binario_in     => digito_binario_calc_s,
            digito_denso_in       => digito_denso_calc_s,
            digito_binario_out    => digito_binario,
            digito_denso_out      => digito_denso,
            resultado_valido      => resultado_valido,
            classificadores_concordam => classificadores_concordam
        );

end architecture arch;

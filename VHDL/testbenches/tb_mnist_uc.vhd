-------------------------------------------------------------------------------
-- Arquivo   : tb_mnist_uc.vhd
-------------------------------------------------------------------------------
-- Descricao : testbench assertivo para mnist_uc.
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     19/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  novo componente
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.mnist_tipos_pkg.all;
use work.tb_uart_mnist_pkg.all;

entity tb_mnist_uc is
end entity tb_mnist_uc;

architecture sim of tb_mnist_uc is

    signal clock : std_logic := '0';
    signal reset : std_logic := '0';

    signal classifica_pulso      : std_logic := '0';
    signal limpa_canvas_pulso    : std_logic := '0';
    signal imagem_alterada_pulso : std_logic := '0';
    signal escrita_habilitada    : std_logic := '0';
    signal imagem_valida         : std_logic := '0';
    signal denso_pronto          : std_logic := '0';

    signal inicia_denso       : std_logic;
    signal registra_resultado : std_logic;
    signal limpa_resultado    : std_logic;
    signal classificacao_ocupada : std_logic;
    signal resultado_pendente    : std_logic;
    signal estado_uc             : estado_uc_t;

begin

    clock <= not clock after TB_CLK_PERIOD_C / 2;

    dut : entity work.mnist_uc
        port map (
            clock                  => clock,
            reset                  => reset,
            classifica_pulso       => classifica_pulso,
            limpa_canvas_pulso     => limpa_canvas_pulso,
            imagem_alterada_pulso  => imagem_alterada_pulso,
            escrita_habilitada     => escrita_habilitada,
            imagem_valida          => imagem_valida,
            denso_pronto           => denso_pronto,
            inicia_denso           => inicia_denso,
            registra_resultado     => registra_resultado,
            limpa_resultado        => limpa_resultado,
            classificacao_ocupada  => classificacao_ocupada,
            resultado_pendente     => resultado_pendente,
            estado_uc              => estado_uc
        );

    stim : process
    begin
        tb_apply_reset(clock, reset);

        assert estado_uc = UC_IDLE_C report "reset nao entrou em IDLE" severity failure;
        assert inicia_denso = '0' report "reset deixou inicia_denso alto" severity failure;
        assert registra_resultado = '0' report "reset deixou registra_resultado alto" severity failure;
        assert limpa_resultado = '0' report "reset deixou limpa_resultado alto" severity failure;
        assert classificacao_ocupada = '0' report "reset deixou classificacao_ocupada alto" severity failure;
        assert resultado_pendente = '0' report "reset deixou resultado_pendente alto" severity failure;

        classifica_pulso <= '1';
        imagem_valida    <= '0';
        wait until rising_edge(clock);
        wait for 1 ns;
        classifica_pulso <= '0';
        assert estado_uc = UC_IDLE_C report "classificacao aceita sem imagem valida" severity failure;

        imagem_valida        <= '1';
        escrita_habilitada   <= '1';
        classifica_pulso     <= '1';
        wait until rising_edge(clock);
        wait for 1 ns;
        classifica_pulso   <= '0';
        escrita_habilitada <= '0';
        assert estado_uc = UC_CLASSIFICA_C
            report "classificacao durante escrita nao entrou em CLASSIFICA"
            severity failure;
        assert inicia_denso = '1' report "CLASSIFICA nao ativou inicia_denso" severity failure;
        assert classificacao_ocupada = '1' report "CLASSIFICA nao ativou classificacao_ocupada" severity failure;
        assert resultado_pendente = '1' report "CLASSIFICA nao ativou resultado_pendente" severity failure;

        wait until rising_edge(clock);
        wait for 1 ns;
        assert estado_uc = UC_AGUARDA_C report "nao entrou em AGUARDA" severity failure;
        assert inicia_denso = '0' report "inicia_denso durou mais de um clock" severity failure;
        assert classificacao_ocupada = '1' report "AGUARDA nao ativou classificacao_ocupada" severity failure;
        assert resultado_pendente = '1' report "AGUARDA nao ativou resultado_pendente" severity failure;

        classifica_pulso <= '1';
        wait until rising_edge(clock);
        wait for 1 ns;
        classifica_pulso <= '0';
        assert estado_uc = UC_AGUARDA_C report "pulso de classificacao alterou estado AGUARDA" severity failure;

        denso_pronto <= '1';
        wait until rising_edge(clock);
        wait for 1 ns;
        denso_pronto <= '0';
        assert estado_uc = UC_REGISTRA_C report "nao entrou em REGISTRA" severity failure;
        assert registra_resultado = '1' report "REGISTRA nao ativou registra_resultado" severity failure;
        assert classificacao_ocupada = '0' report "REGISTRA nao deveria manter classificacao_ocupada" severity failure;
        assert resultado_pendente = '1' report "REGISTRA nao manteve resultado_pendente alto" severity failure;

        wait until rising_edge(clock);
        wait for 1 ns;
        assert estado_uc = UC_PRONTO_C report "nao entrou em PRONTO" severity failure;
        assert registra_resultado = '0' report "registra_resultado durou mais de um clock" severity failure;
        assert resultado_pendente = '0' report "PRONTO deveria limpar resultado_pendente" severity failure;

        limpa_canvas_pulso <= '1';
        wait until rising_edge(clock);
        wait for 1 ns;
        limpa_canvas_pulso <= '0';
        assert limpa_resultado = '1' report "limpa_canvas nao ativou limpa_resultado" severity failure;
        assert estado_uc = UC_IDLE_C report "limpa_canvas fora da classificacao nao entrou em IDLE" severity failure;

        wait until rising_edge(clock);
        wait for 1 ns;
        assert limpa_resultado = '0' report "limpa_resultado durou mais de um clock" severity failure;

        classifica_pulso <= '1';
        wait until rising_edge(clock);
        wait for 1 ns;
        classifica_pulso <= '0';
        assert estado_uc = UC_CLASSIFICA_C report "segunda classificacao nao entrou em CLASSIFICA" severity failure;

        wait until rising_edge(clock);
        wait for 1 ns;
        assert estado_uc = UC_AGUARDA_C report "segunda classificacao nao entrou em AGUARDA" severity failure;

        imagem_alterada_pulso <= '1';
        wait until rising_edge(clock);
        wait for 1 ns;
        imagem_alterada_pulso <= '0';
        assert limpa_resultado = '1' report "alteracao de imagem nao ativou limpa_resultado" severity failure;
        assert estado_uc = UC_AGUARDA_C report "alteracao de imagem durante espera deveria permanecer em AGUARDA" severity failure;
        assert registra_resultado = '0' report "alteracao de imagem durante espera registrou resultado" severity failure;

        denso_pronto <= '1';
        wait until rising_edge(clock);
        wait for 1 ns;
        denso_pronto <= '0';
        assert estado_uc = UC_IDLE_C report "resultado descartado nao retornou para IDLE" severity failure;
        assert registra_resultado = '0' report "resultado descartado ativou registra_resultado" severity failure;
        assert resultado_pendente = '0' report "resultado descartado deixou resultado_pendente alto" severity failure;

        classifica_pulso <= '1';
        wait until rising_edge(clock);
        wait for 1 ns;
        classifica_pulso <= '0';
        wait until rising_edge(clock);
        wait for 1 ns;
        assert estado_uc = UC_AGUARDA_C report "terceira classificacao nao chegou em AGUARDA" severity failure;

        limpa_canvas_pulso <= '1';
        denso_pronto       <= '1';
        wait until rising_edge(clock);
        wait for 1 ns;
        limpa_canvas_pulso <= '0';
        denso_pronto       <= '0';
        assert estado_uc = UC_AGUARDA_C report "limpeza/pronto simultaneos deveriam manter AGUARDA para descarte" severity failure;
        assert registra_resultado = '0' report "limpeza/pronto simultaneos registraram resultado" severity failure;

        denso_pronto <= '1';
        wait until rising_edge(clock);
        wait for 1 ns;
        denso_pronto <= '0';
        assert estado_uc = UC_IDLE_C report "descarte apos limpeza/pronto simultaneos nao entrou em IDLE" severity failure;
        assert registra_resultado = '0' report "descarte apos limpeza/pronto simultaneos registrou resultado" severity failure;

        report "tb_mnist_uc concluido" severity note;
        stop;
    end process;

end architecture sim;

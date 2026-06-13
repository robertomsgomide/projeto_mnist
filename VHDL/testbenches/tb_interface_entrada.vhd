-------------------------------------------------------------------------------
-- Arquivo   : tb_interface_entrada.vhd
-------------------------------------------------------------------------------
-- Descricao : testbench assertivo para interface_entrada.
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     19/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  novo componente
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.tb_uart_mnist_pkg.all;

entity tb_interface_entrada is
end entity tb_interface_entrada;

architecture sim of tb_interface_entrada is

    signal clock : std_logic := '0';

    signal escreve    : std_logic := '0';
    signal apaga      : std_logic := '0';
    signal classifica : std_logic := '0';

    signal escrita_habilitada : std_logic;
    signal limpa_canvas_pulso : std_logic;
    signal classifica_pulso   : std_logic;

begin

    clock <= not clock after TB_CLK_PERIOD_C / 2;

    dut : entity work.interface_entrada
        port map (
            clock               => clock,
            escreve             => escreve,
            apaga               => apaga,
            classifica          => classifica,
            escrita_habilitada  => escrita_habilitada,
            limpa_canvas_pulso  => limpa_canvas_pulso,
            classifica_pulso    => classifica_pulso
        );

    stim : process
    begin
        tb_wait_cycles(clock, 5);

        assert escrita_habilitada = '0'
            report "escrita_habilitada inicial nao esta baixa"
            severity failure;
        assert limpa_canvas_pulso = '0'
            report "pulso inicial de limpa_canvas nao esta baixo"
            severity failure;
        assert classifica_pulso = '0'
            report "pulso inicial de classifica nao esta baixo"
            severity failure;

        escreve <= '1';
        tb_wait_cycles(clock, 2);
        assert escrita_habilitada = '1'
            report "escreve=1 nao habilitou escrita apos sincronismo"
            severity failure;
        assert limpa_canvas_pulso = '0'
            report "escreve gerou pulso de limpeza"
            severity failure;
        assert classifica_pulso = '0'
            report "escreve gerou pulso de classificacao"
            severity failure;

        escreve <= '0';
        tb_wait_cycles(clock, 2);
        assert escrita_habilitada = '0'
            report "escreve=0 nao bloqueou escrita apos sincronismo"
            severity failure;

        apaga <= '1';
        tb_wait_cycles(clock, 2);
        tb_expect_one_cycle_high(clock, limpa_canvas_pulso, "borda de subida de apaga");

        tb_wait_cycles(clock, 3);
        assert limpa_canvas_pulso = '0'
            report "apaga mantido gerou pulso de limpeza repetido"
            severity failure;

        apaga <= '0';
        tb_wait_cycles(clock, 2);
        assert limpa_canvas_pulso = '0'
            report "borda de descida de apaga gerou pulso de limpeza"
            severity failure;

        escreve <= '1';
        tb_wait_cycles(clock, 2);
        assert escrita_habilitada = '1'
            report "escrita_habilitada nao esta alta antes do teste de classificacao"
            severity failure;

        classifica <= '1';
        tb_wait_cycles(clock, 2);
        assert escrita_habilitada = '1'
            report "classifica alterou escrita_habilitada"
            severity failure;
        tb_expect_one_cycle_high(
            clock,
            classifica_pulso,
            "borda de subida de classifica durante escrita"
        );

        tb_wait_cycles(clock, 3);
        assert classifica_pulso = '0'
            report "classifica mantido gerou pulso de classificacao repetido"
            severity failure;

        classifica <= '0';
        escreve    <= '0';
        tb_wait_cycles(clock, 2);
        assert classifica_pulso = '0'
            report "borda de descida de classifica gerou pulso de classificacao"
            severity failure;
        assert escrita_habilitada = '0'
            report "escrita_habilitada nao esta baixa no fim"
            severity failure;

        report "tb_interface_entrada concluido" severity note;
        stop;
    end process;

end architecture sim;

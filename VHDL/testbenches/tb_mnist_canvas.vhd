-------------------------------------------------------------------------------
-- Arquivo   : tb_mnist_canvas.vhd
-------------------------------------------------------------------------------
-- Descricao : testbench assertivo para mnist_canvas.
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     19/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  versao inicial
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.mnist_tipos_pkg.all;
use work.tb_uart_mnist_pkg.all;

entity tb_mnist_canvas is
end entity tb_mnist_canvas;

architecture sim of tb_mnist_canvas is

    signal clock : std_logic := '0';
    signal reset : std_logic := '0';

    signal limpa_canvas_pulso : std_logic := '0';
    signal escrita_habilitada : std_logic := '0';

    signal frame_recebido        : imagem_mnist_t := (others => '0');
    signal frame_recebido_valido : std_logic := '0';

    signal imagem_atual          : imagem_mnist_t;
    signal imagem_valida         : std_logic;
    signal imagem_alterada_pulso : std_logic;

    constant ZERO_IMAGE_C : imagem_mnist_t := (others => '0');

    procedure pulse_frame(
        signal clock_p      : in std_logic;
        signal frame_p      : out imagem_mnist_t;
        signal frame_valid_p : out std_logic;
        frame               : in imagem_mnist_t
    ) is
    begin
        frame_p       <= frame;
        frame_valid_p <= '1';
        wait until rising_edge(clock_p);
        wait for 1 ns;
        frame_valid_p <= '0';
    end procedure;

begin

    clock <= not clock after TB_CLK_PERIOD_C / 2;

    dut : entity work.mnist_canvas
        port map (
            clock                  => clock,
            reset                  => reset,
            limpa_canvas_pulso     => limpa_canvas_pulso,
            escrita_habilitada     => escrita_habilitada,
            frame_recebido         => frame_recebido,
            frame_recebido_valido  => frame_recebido_valido,
            imagem_atual           => imagem_atual,
            imagem_valida          => imagem_valida,
            imagem_alterada_pulso  => imagem_alterada_pulso
        );

    stim : process
        variable frame_a_v : imagem_mnist_t := (others => '0');
        variable frame_b_v : imagem_mnist_t := (others => '0');
        variable frame_c_v : imagem_mnist_t := (others => '0');
    begin
        frame_a_v(0)   := '1';
        frame_a_v(7)   := '1';
        frame_a_v(128) := '1';

        frame_b_v(7)   := '1';
        frame_b_v(321) := '1';

        frame_c_v(12)  := '1';

        tb_apply_reset(clock, reset);

        assert imagem_atual = ZERO_IMAGE_C
            report "reset nao limpou imagem_atual"
            severity failure;
        assert imagem_valida = '0'
            report "reset nao limpou imagem_valida"
            severity failure;
        assert imagem_alterada_pulso = '0'
            report "reset deixou imagem_alterada_pulso alto"
            severity failure;

        escrita_habilitada <= '0';
        pulse_frame(clock, frame_recebido, frame_recebido_valido, frame_a_v);
        assert imagem_atual = ZERO_IMAGE_C
            report "frame bloqueado alterou imagem_atual"
            severity failure;
        assert imagem_valida = '0'
            report "frame bloqueado ativou imagem_valida"
            severity failure;
        assert imagem_alterada_pulso = '0'
            report "frame bloqueado gerou imagem_alterada_pulso"
            severity failure;

        escrita_habilitada <= '1';
        pulse_frame(clock, frame_recebido, frame_recebido_valido, frame_a_v);
        assert imagem_atual = frame_a_v
            report "escrita habilitada nao armazenou o frame"
            severity failure;
        assert imagem_valida = '1'
            report "escrita habilitada nao ativou imagem_valida"
            severity failure;
        assert imagem_alterada_pulso = '1'
            report "escrita habilitada nao pulsou imagem_alterada_pulso"
            severity failure;
        tb_expect_one_cycle_high(clock, imagem_alterada_pulso, "primeira escrita alterou imagem");

        pulse_frame(clock, frame_recebido, frame_recebido_valido, frame_b_v);
        assert imagem_atual = frame_b_v
            report "segundo frame nao substituiu o primeiro frame"
            severity failure;
        assert imagem_valida = '1'
            report "segundo frame limpou imagem_valida"
            severity failure;
        assert imagem_alterada_pulso = '1'
            report "segundo frame nao pulsou imagem_alterada_pulso"
            severity failure;
        assert imagem_atual(0) = '0' and imagem_atual(128) = '0' and imagem_atual(321) = '1'
            report "segundo frame nao limpou pixels ausentes nele"
            severity failure;
        tb_expect_one_cycle_high(clock, imagem_alterada_pulso, "frame substituto alterou imagem");

        pulse_frame(clock, frame_recebido, frame_recebido_valido, frame_b_v);
        assert imagem_atual = frame_b_v
            report "frame repetido alterou imagem armazenada"
            severity failure;
        assert imagem_alterada_pulso = '1'
            report "frame repetido aceito nao pulsou imagem_alterada_pulso"
            severity failure;
        tb_expect_one_cycle_high(clock, imagem_alterada_pulso, "frame repetido alterou imagem");

        pulse_frame(clock, frame_recebido, frame_recebido_valido, ZERO_IMAGE_C);
        assert imagem_atual = ZERO_IMAGE_C
            report "frame zerado nao limpou imagem_atual"
            severity failure;
        assert imagem_valida = '0'
            report "frame zerado nao limpou imagem_valida"
            severity failure;
        assert imagem_alterada_pulso = '1'
            report "frame zerado aceito nao pulsou imagem_alterada_pulso"
            severity failure;
        tb_expect_one_cycle_high(clock, imagem_alterada_pulso, "frame zerado alterou imagem");

        pulse_frame(clock, frame_recebido, frame_recebido_valido, frame_a_v);
        assert imagem_atual = frame_a_v
            report "recarga antes da prioridade de limpeza falhou"
            severity failure;
        tb_expect_one_cycle_high(clock, imagem_alterada_pulso, "recarga antes da limpeza alterou imagem");

        limpa_canvas_pulso     <= '1';
        frame_recebido         <= frame_c_v;
        frame_recebido_valido  <= '1';
        wait until rising_edge(clock);
        wait for 1 ns;
        limpa_canvas_pulso     <= '0';
        frame_recebido_valido  <= '0';

        assert imagem_atual = ZERO_IMAGE_C
            report "prioridade de limpeza nao limpou imagem_atual"
            severity failure;
        assert imagem_valida = '0'
            report "prioridade de limpeza nao limpou imagem_valida"
            severity failure;
        assert imagem_alterada_pulso = '1'
            report "limpeza nao pulsou imagem_alterada_pulso"
            severity failure;
        tb_expect_one_cycle_high(clock, imagem_alterada_pulso, "limpeza de imagem valida alterou imagem");

        limpa_canvas_pulso <= '1';
        wait until rising_edge(clock);
        wait for 1 ns;
        limpa_canvas_pulso <= '0';

        assert imagem_atual = ZERO_IMAGE_C
            report "segunda limpeza alterou imagem_atual"
            severity failure;
        assert imagem_valida = '0'
            report "segunda limpeza ativou imagem_valida"
            severity failure;
        assert imagem_alterada_pulso = '1'
            report "limpeza de imagem invalida nao pulsou imagem_alterada_pulso"
            severity failure;
        tb_expect_one_cycle_high(clock, imagem_alterada_pulso, "limpeza de imagem invalida alterou imagem");

        report "tb_mnist_canvas concluido" severity note;
        stop;
    end process;

end architecture sim;

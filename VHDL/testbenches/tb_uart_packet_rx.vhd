-------------------------------------------------------------------------------
-- Arquivo   : tb_uart_packet_rx.vhd
-------------------------------------------------------------------------------
-- Descricao : testbench assertivo para uart_packet_rx.
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     20/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  versao inicial
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.mnist_tipos_pkg.all;
use work.tb_uart_mnist_pkg.all;

entity tb_uart_packet_rx is
end entity tb_uart_packet_rx;

architecture sim of tb_uart_packet_rx is

    signal clock : std_logic := '0';
    signal reset : std_logic := '0';

    signal byte_rx     : uart_byte_t := (others => '0');
    signal byte_valido : std_logic := '0';
    signal erro_frame  : std_logic := '0';

    signal payload_byte   : uart_byte_t;
    signal payload_indice : uart_payload_index_t;
    signal payload_valido : std_logic;

    signal cmd_rx      : uart_byte_t;
    signal seq_rx      : uart_seq_t;
    signal payload_len : uart_len_t;

    signal pacote_valido   : std_logic;
    signal pacote_invalido : std_logic;
    signal erro_codigo     : uart_erro_t;
    signal ocupado         : std_logic;

    procedure send_valid_packet(
        signal clock_p       : in std_logic;
        signal byte_rx_p     : out uart_byte_t;
        signal byte_valido_p : out std_logic;
        seq                  : in uart_seq_t;
        payload              : in uart_frame_payload_t
    ) is
        variable checksum_v : uart_byte_t;
    begin
        checksum_v := tb_packet_checksum(
            UART_CMD_FRAME_C,
            TB_UART_LEN_L_C,
            TB_UART_LEN_H_C,
            seq,
            payload
        );

        tb_pulse_parallel_byte(clock_p, byte_rx_p, byte_valido_p, UART_HEADER0_C);
        assert ocupado = '1' report "ocupado deveria subir apos HEADER0" severity failure;

        tb_pulse_parallel_byte(clock_p, byte_rx_p, byte_valido_p, UART_HEADER1_C);
        tb_pulse_parallel_byte(clock_p, byte_rx_p, byte_valido_p, UART_CMD_FRAME_C);
        tb_pulse_parallel_byte(clock_p, byte_rx_p, byte_valido_p, TB_UART_LEN_L_C);
        tb_pulse_parallel_byte(clock_p, byte_rx_p, byte_valido_p, TB_UART_LEN_H_C);
        tb_pulse_parallel_byte(clock_p, byte_rx_p, byte_valido_p, seq);

        for i in payload'range loop
            tb_pulse_parallel_byte(clock_p, byte_rx_p, byte_valido_p, payload(i));

            assert payload_valido = '1'
                report "payload_valido ausente"
                severity failure;
            assert payload_byte = payload(i)
                report "payload_byte divergente no indice " & integer'image(i)
                severity failure;
            assert payload_indice = to_unsigned(i, payload_indice'length)
                report "payload_indice divergente no indice " & integer'image(i)
                severity failure;
        end loop;

        tb_pulse_parallel_byte(clock_p, byte_rx_p, byte_valido_p, checksum_v);

        assert pacote_valido = '1'
            report "pacote valido nao ativou pacote_valido"
            severity failure;
        assert pacote_invalido = '0'
            report "pacote valido ativou pacote_invalido"
            severity failure;
        assert erro_codigo = UART_ERRO_NENHUM_C
            report "pacote valido deixou codigo de erro"
            severity failure;
        assert cmd_rx = UART_CMD_FRAME_C
            report "cmd_rx divergente apos pacote valido"
            severity failure;
        assert seq_rx = seq
            report "seq_rx divergente apos pacote valido"
            severity failure;
        assert payload_len = to_unsigned(UART_PAYLOAD_FRAME_BYTES_C, payload_len'length)
            report "payload_len divergente apos pacote valido"
            severity failure;

        tb_expect_one_cycle_high(clock_p, pacote_valido, "pacote_valido");
        assert ocupado = '0' report "ocupado deveria limpar apos pacote" severity failure;
    end procedure;

begin

    clock <= not clock after TB_CLK_PERIOD_C / 2;

    dut : entity work.uart_packet_rx
        port map (
            clock           => clock,
            reset           => reset,
            byte_rx         => byte_rx,
            byte_valido     => byte_valido,
            erro_frame      => erro_frame,
            payload_byte    => payload_byte,
            payload_indice  => payload_indice,
            payload_valido  => payload_valido,
            cmd_rx          => cmd_rx,
            seq_rx          => seq_rx,
            payload_len     => payload_len,
            pacote_valido   => pacote_valido,
            pacote_invalido => pacote_invalido,
            erro_codigo     => erro_codigo,
            ocupado         => ocupado
        );

    stim : process
        variable payload_a_v : uart_frame_payload_t := tb_make_payload(16);
        variable payload_b_v : uart_frame_payload_t := tb_make_payload(91);
        variable checksum_v  : uart_byte_t;
    begin
        tb_apply_reset(clock, reset);

        assert ocupado = '0' report "reset nao limpou ocupado" severity failure;
        assert payload_valido = '0' report "reset deixou payload_valido alto" severity failure;
        assert pacote_valido = '0' report "reset deixou pacote_valido alto" severity failure;
        assert pacote_invalido = '0' report "reset deixou pacote_invalido alto" severity failure;
        assert erro_codigo = UART_ERRO_NENHUM_C report "codigo de erro divergente apos reset" severity failure;

        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, x"00");
        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, x"42");
        assert ocupado = '0' report "ruido antes de HEADER0 deveria ser ignorado" severity failure;

        send_valid_packet(clock, byte_rx, byte_valido, x"23", payload_a_v);

        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, UART_HEADER0_C);
        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, UART_HEADER0_C);
        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, UART_HEADER1_C);
        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, UART_CMD_FRAME_C);
        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, TB_UART_LEN_L_C);
        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, TB_UART_LEN_H_C);
        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, x"24");

        for i in payload_b_v'range loop
            tb_pulse_parallel_byte(clock, byte_rx, byte_valido, payload_b_v(i));
            assert payload_valido = '1'
                report "pulso de payload ausente no pacote de ressincronizacao"
                severity failure;
        end loop;

        checksum_v := tb_packet_checksum(
            UART_CMD_FRAME_C,
            TB_UART_LEN_L_C,
            TB_UART_LEN_H_C,
            x"24",
            payload_b_v
        );
        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, checksum_v);
        assert pacote_valido = '1' report "pacote de ressincronizacao nao aceito" severity failure;
        tb_expect_one_cycle_high(clock, pacote_valido, "pacote_valido de ressincronizacao");

        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, UART_HEADER0_C);
        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, x"00");
        assert pacote_invalido = '1' report "header invalido nao ativou pacote_invalido" severity failure;
        assert erro_codigo = UART_ERRO_HEADER_C report "codigo de erro divergente para header invalido" severity failure;
        assert seq_rx = x"00" report "header invalido reutilizou sequencia" severity failure;
        tb_expect_one_cycle_high(clock, pacote_invalido, "header invalido");

        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, UART_HEADER0_C);
        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, UART_HEADER1_C);
        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, x"7E");
        assert pacote_invalido = '1' report "comando invalido nao ativou pacote_invalido" severity failure;
        assert erro_codigo = UART_ERRO_COMANDO_C report "codigo de erro divergente para comando invalido" severity failure;
        tb_expect_one_cycle_high(clock, pacote_invalido, "comando invalido");

        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, UART_HEADER0_C);
        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, UART_HEADER1_C);
        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, UART_CMD_FRAME_C);
        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, x"61");
        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, x"00");
        assert pacote_invalido = '1' report "tamanho invalido nao ativou pacote_invalido" severity failure;
        assert erro_codigo = UART_ERRO_TAMANHO_C report "codigo de erro divergente para tamanho invalido" severity failure;
        tb_expect_one_cycle_high(clock, pacote_invalido, "tamanho invalido");

        checksum_v := tb_packet_checksum(
            UART_CMD_FRAME_C,
            TB_UART_LEN_L_C,
            TB_UART_LEN_H_C,
            x"25",
            payload_a_v
        ) xor x"FF";

        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, UART_HEADER0_C);
        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, UART_HEADER1_C);
        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, UART_CMD_FRAME_C);
        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, TB_UART_LEN_L_C);
        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, TB_UART_LEN_H_C);
        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, x"25");

        for i in payload_a_v'range loop
            tb_pulse_parallel_byte(clock, byte_rx, byte_valido, payload_a_v(i));
        end loop;

        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, checksum_v);
        assert pacote_invalido = '1' report "checksum invalido nao ativou pacote_invalido" severity failure;
        assert erro_codigo = UART_ERRO_CHECKSUM_C report "codigo de erro divergente para checksum invalido" severity failure;
        assert seq_rx = x"25" report "checksum invalido nao preservou seq" severity failure;
        tb_expect_one_cycle_high(clock, pacote_invalido, "checksum invalido");

        tb_pulse_std_logic(clock, erro_frame);
        assert pacote_invalido = '0' report "erro de frame em repouso nao deveria ativar pacote_invalido" severity failure;
        assert erro_codigo = UART_ERRO_FRAME_C report "codigo de erro divergente para erro de frame em repouso" severity failure;
        assert seq_rx = x"00" report "erro de frame em repouso deveria limpar seq" severity failure;

        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, UART_HEADER0_C);
        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, UART_HEADER1_C);
        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, UART_CMD_FRAME_C);
        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, TB_UART_LEN_L_C);
        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, TB_UART_LEN_H_C);
        tb_pulse_std_logic(clock, erro_frame);
        assert pacote_invalido = '1' report "erro de frame antes de SEQ nao invalidou pacote" severity failure;
        assert erro_codigo = UART_ERRO_FRAME_C report "codigo de erro divergente para frame antes de SEQ" severity failure;
        assert seq_rx = x"00" report "erro de frame antes de SEQ reutilizou seq antiga" severity failure;
        tb_expect_one_cycle_high(clock, pacote_invalido, "frame antes de SEQ invalido");

        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, UART_HEADER0_C);
        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, UART_HEADER1_C);
        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, UART_CMD_FRAME_C);
        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, TB_UART_LEN_L_C);
        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, TB_UART_LEN_H_C);
        tb_pulse_parallel_byte(clock, byte_rx, byte_valido, x"BE");
        tb_pulse_std_logic(clock, erro_frame);
        assert pacote_invalido = '1' report "erro de frame apos SEQ nao invalidou pacote" severity failure;
        assert erro_codigo = UART_ERRO_FRAME_C report "codigo de erro divergente para frame apos SEQ" severity failure;
        assert seq_rx = x"BE" report "erro de frame apos SEQ nao preservou seq" severity failure;
        tb_expect_one_cycle_high(clock, pacote_invalido, "frame apos SEQ invalido");

        report "tb_uart_packet_rx concluido" severity note;
        stop;
    end process;

end architecture sim;

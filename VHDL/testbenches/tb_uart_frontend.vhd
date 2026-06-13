-------------------------------------------------------------------------------
-- Arquivo   : tb_uart_frontend.vhd
-------------------------------------------------------------------------------
-- Descricao : testbench assertivo para uart_frontend com UART serial real.
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     20/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  novo componente
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.mnist_tipos_pkg.all;
use work.tb_uart_mnist_pkg.all;

entity tb_uart_frontend is
end entity tb_uart_frontend;

architecture sim of tb_uart_frontend is

    signal clock : std_logic := '0';
    signal reset : std_logic := '0';

    signal uart_rx_serial : std_logic := '1';
    signal uart_tx_serial : std_logic;

    signal frame_recebido        : imagem_mnist_t;
    signal frame_recebido_valido : std_logic;

    signal uart_recebendo    : std_logic;
    signal pacote_ok_pulso   : std_logic;
    signal pacote_erro_pulso : std_logic;
    signal erro_codigo       : uart_erro_t;
    signal seq_ultimo        : uart_seq_t;

    procedure check_response(
        packet    : in uart_response_packet_t;
        cmd       : in uart_byte_t;
        seq       : in uart_seq_t;
        erro_byte : in uart_byte_t;
        msg       : in string
    ) is
    begin
        for i in packet'range loop
            assert packet(i) = tb_response_byte(i, cmd, seq, erro_byte)
                report msg & ": byte de resposta " & integer'image(i) & " divergente"
                severity failure;
        end loop;
    end procedure;

begin

    clock <= not clock after TB_CLK_PERIOD_C / 2;

    dut : entity work.uart_frontend
        port map (
            clock                  => clock,
            reset                  => reset,
            uart_rx_serial         => uart_rx_serial,
            uart_tx_serial         => uart_tx_serial,
            frame_recebido         => frame_recebido,
            frame_recebido_valido  => frame_recebido_valido,
            uart_recebendo         => uart_recebendo,
            pacote_ok_pulso        => pacote_ok_pulso,
            pacote_erro_pulso      => pacote_erro_pulso,
            erro_codigo            => erro_codigo,
            seq_ultimo             => seq_ultimo
        );

    stim : process
        variable payload_a_v   : uart_frame_payload_t := tb_make_payload(19);
        variable payload_b_v   : uart_frame_payload_t := tb_make_payload(73);
        variable payload_c_v   : uart_frame_payload_t := tb_make_payload(127);
        variable payload_d_v   : uart_frame_payload_t := tb_make_payload(201);
        variable ack_v         : uart_response_packet_t;
        variable old_frame_v   : imagem_mnist_t := (others => '0');
    begin
        tb_apply_reset(clock, reset);

        assert uart_tx_serial = '1' report "TX serial deveria ficar alto em repouso apos reset" severity failure;
        assert frame_recebido_valido = '0' report "reset deixou frame_recebido_valido alto" severity failure;
        assert pacote_ok_pulso = '0' report "reset deixou pacote_ok_pulso alto" severity failure;
        assert pacote_erro_pulso = '0' report "reset deixou pacote_erro_pulso alto" severity failure;
        assert erro_codigo = UART_ERRO_NENHUM_C report "codigo de erro divergente apos reset" severity failure;

        tb_send_uart_frame_packet(uart_rx_serial, x"11", payload_a_v, x"00");
        tb_wait_for_pulse(clock, pacote_ok_pulso, 500, "OK de pacote valido");
        assert seq_ultimo = x"11" report "sequencia divergente no pacote valido" severity failure;
        assert frame_recebido_valido = '0'
            report "frame_recebido_valido deveria atrasar um clock em relacao ao pulso OK"
            severity failure;
        assert erro_codigo = UART_ERRO_NENHUM_C
            report "primeiro pacote valido deveria manter codigo sem erro"
            severity failure;

        wait until rising_edge(clock);
        wait for 1 ns;
        assert frame_recebido_valido = '1'
            report "frame_recebido_valido nao ocorreu um clock apos OK"
            severity failure;
        assert frame_recebido = tb_payload_to_image(payload_a_v)
            report "frame divergente no pacote valido"
            severity failure;
        tb_expect_one_cycle_high(clock, frame_recebido_valido, "frame de pacote valido");

        tb_recv_uart_response(uart_tx_serial, ack_v);
        check_response(ack_v, UART_CMD_ACK_C, x"11", x"00", "ACK para pacote valido");

        old_frame_v := frame_recebido;
        tb_send_uart_frame_packet(uart_rx_serial, x"22", payload_b_v, x"FF");
        tb_wait_for_pulse(clock, pacote_erro_pulso, 500, "pulso de erro de checksum");
        assert seq_ultimo = x"22" report "sequencia divergente no erro de checksum" severity failure;
        assert frame_recebido_valido = '0'
            report "erro de checksum gerou frame_recebido_valido no pulso de erro"
            severity failure;

        wait until rising_edge(clock);
        wait for 1 ns;
        assert erro_codigo = UART_ERRO_CHECKSUM_C
            report "codigo de erro de checksum nao foi registrado um clock depois"
            severity failure;
        assert frame_recebido_valido = '0'
            report "erro de checksum gerou frame_recebido_valido atrasado"
            severity failure;
        assert frame_recebido = old_frame_v
            report "erro de checksum alterou saida frame_recebido"
            severity failure;

        tb_recv_uart_response(uart_tx_serial, ack_v);
        check_response(
            ack_v,
            UART_CMD_NACK_C,
            x"22",
            "0000" & UART_ERRO_CHECKSUM_C,
            "NACK para erro de checksum"
        );

        tb_send_uart_byte(uart_rx_serial, UART_HEADER0_C);
        tb_send_uart_byte(uart_rx_serial, UART_HEADER1_C);
        tb_send_uart_byte(uart_rx_serial, UART_CMD_FRAME_C);
        tb_send_uart_byte(uart_rx_serial, TB_UART_LEN_L_C);
        tb_send_uart_byte(uart_rx_serial, TB_UART_LEN_H_C);
        tb_send_uart_byte(uart_rx_serial, x"33");
        tb_send_uart_bad_frame_until_pulse(
            uart_rx_serial,
            clock,
            pacote_erro_pulso,
            x"55",
            500,
            "erro de frame no pacote"
        );
        assert seq_ultimo = x"33" report "erro de frame nao preservou sequencia" severity failure;
        assert frame_recebido_valido = '0'
            report "erro de frame gerou frame_recebido_valido"
            severity failure;
        uart_rx_serial <= '1';

        wait until rising_edge(clock);
        wait for 1 ns;
        assert erro_codigo = UART_ERRO_FRAME_C
            report "codigo de erro de frame nao foi registrado um clock depois"
            severity failure;

        tb_recv_uart_response(uart_tx_serial, ack_v);
        check_response(
            ack_v,
            UART_CMD_NACK_C,
            x"33",
            "0000" & UART_ERRO_FRAME_C,
            "NACK para erro de frame"
        );

        tb_send_uart_bad_frame_until_pulse(
            uart_rx_serial,
            clock,
            pacote_erro_pulso,
            x"00",
            500,
            "erro de frame em repouso"
        );
        assert frame_recebido_valido = '0'
            report "erro de frame em repouso gerou frame_recebido_valido"
            severity failure;
        uart_rx_serial <= '1';

        wait until rising_edge(clock);
        wait for 1 ns;
        assert erro_codigo = UART_ERRO_FRAME_C
            report "codigo de erro de frame em repouso nao foi registrado"
            severity failure;

        tb_wait_cycles(clock, 40);
        assert uart_tx_serial = '1'
            report "erro de frame em repouso iniciou ACK/NACK inesperadamente"
            severity failure;

        tb_send_uart_frame_packet(uart_rx_serial, x"44", payload_c_v, x"00");
        tb_wait_for_pulse(clock, pacote_ok_pulso, 500, "pacote valido apos erros");
        assert seq_ultimo = x"44" report "sequencia divergente no pacote valido apos erros" severity failure;
        assert erro_codigo = UART_ERRO_FRAME_C
            report "erro_codigo deveria limpar um clock apos OK, nao no pulso OK"
            severity failure;

        wait until rising_edge(clock);
        wait for 1 ns;
        assert erro_codigo = UART_ERRO_NENHUM_C
            report "pacote valido nao limpou codigo de erro um clock depois"
            severity failure;
        assert frame_recebido_valido = '1'
            report "pacote valido apos erros nao emitiu frame"
            severity failure;
        assert frame_recebido = tb_payload_to_image(payload_c_v)
            report "frame divergente no pacote valido apos erros"
            severity failure;
        tb_expect_one_cycle_high(clock, frame_recebido_valido, "frame valido apos erros");

        tb_recv_uart_response(uart_tx_serial, ack_v);
        check_response(ack_v, UART_CMD_ACK_C, x"44", x"00", "ACK apos erros");

        tb_send_uart_frame_packet(uart_rx_serial, x"45", payload_d_v, x"00");
        tb_wait_for_pulse(clock, pacote_ok_pulso, 500, "segundo pacote valido consecutivo");
        assert seq_ultimo = x"45" report "sequencia divergente no segundo pacote valido" severity failure;

        wait until rising_edge(clock);
        wait for 1 ns;
        assert frame_recebido_valido = '1'
            report "segundo pacote valido nao emitiu frame"
            severity failure;
        assert frame_recebido = tb_payload_to_image(payload_d_v)
            report "frame divergente no segundo pacote valido"
            severity failure;
        assert erro_codigo = UART_ERRO_NENHUM_C
            report "segundo pacote valido manteve codigo de erro antigo"
            severity failure;
        tb_expect_one_cycle_high(clock, frame_recebido_valido, "segundo frame valido");

        tb_recv_uart_response(uart_tx_serial, ack_v);
        check_response(ack_v, UART_CMD_ACK_C, x"45", x"00", "ACK para segundo pacote valido");

        report "tb_uart_frontend concluido" severity note;
        stop;
    end process;

end architecture sim;

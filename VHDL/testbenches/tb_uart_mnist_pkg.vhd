-------------------------------------------------------------------------------
-- Arquivo   : tb_uart_mnist_pkg.vhd
-------------------------------------------------------------------------------
-- Descricao : utilitarios compartilhados pelos testbenches de UART, canvas e UC.
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     20/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  versao inicial
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;

package tb_uart_mnist_pkg is

    constant TB_CLK_PERIOD_C : time := 20 ns;
    constant TB_BIT_TIME_C   : time :=
        TB_CLK_PERIOD_C * (CLOCK_FREQ_HZ_C / UART_BAUD_C);

    constant TB_UART_LEN_L_C : uart_byte_t :=
        std_logic_vector(to_unsigned(UART_PAYLOAD_FRAME_BYTES_C mod 256, 8));
    constant TB_UART_LEN_H_C : uart_byte_t :=
        std_logic_vector(to_unsigned(UART_PAYLOAD_FRAME_BYTES_C / 256, 8));

    type uart_payload_array_t is array (natural range <>) of uart_byte_t;
    subtype uart_frame_payload_t is
        uart_payload_array_t(0 to UART_PAYLOAD_FRAME_BYTES_C - 1);

    subtype uart_response_packet_t is uart_payload_array_t(0 to 7);

    function tb_make_payload(seed : natural) return uart_frame_payload_t;

    function tb_payload_to_image(
        payload : uart_frame_payload_t
    ) return imagem_mnist_t;

    function tb_packet_checksum(
        cmd     : uart_byte_t;
        len_l   : uart_byte_t;
        len_h   : uart_byte_t;
        seq     : uart_seq_t;
        payload : uart_frame_payload_t
    ) return uart_byte_t;

    function tb_response_checksum(
        cmd        : uart_byte_t;
        seq        : uart_seq_t;
        erro_byte  : uart_byte_t
    ) return uart_byte_t;

    function tb_response_byte(
        indice    : natural;
        cmd       : uart_byte_t;
        seq       : uart_seq_t;
        erro_byte : uart_byte_t
    ) return uart_byte_t;

    procedure tb_wait_cycles(
        signal clock : in std_logic;
        cycles       : in natural
    );

    procedure tb_apply_reset(
        signal clock : in std_logic;
        signal reset : out std_logic
    );

    procedure tb_pulse_parallel_byte(
        signal clock       : in std_logic;
        signal byte_rx     : out uart_byte_t;
        signal byte_valido : out std_logic;
        value              : in uart_byte_t
    );

    procedure tb_pulse_std_logic(
        signal clock : in std_logic;
        signal value : out std_logic
    );

    procedure tb_expect_one_cycle_high(
        signal clock : in std_logic;
        signal pulse : in std_logic;
        msg          : in string
    );

    procedure tb_wait_for_pulse(
        signal clock : in std_logic;
        signal pulse : in std_logic;
        max_cycles   : in natural;
        msg          : in string
    );

    procedure tb_send_uart_byte(
        signal tx_serial : out std_logic;
        value            : in uart_byte_t
    );

    procedure tb_send_uart_bad_frame(
        signal tx_serial : out std_logic;
        value            : in uart_byte_t
    );

    procedure tb_send_uart_bad_frame_until_pulse(
        signal tx_serial : out std_logic;
        signal clock     : in std_logic;
        signal pulse     : in std_logic;
        value            : in uart_byte_t;
        max_cycles       : in natural;
        msg              : in string
    );

    procedure tb_send_uart_frame_packet(
        signal tx_serial : out std_logic;
        seq              : in uart_seq_t;
        payload          : in uart_frame_payload_t;
        checksum_xor     : in uart_byte_t
    );

    procedure tb_recv_uart_byte(
        signal rx_serial : in std_logic;
        variable value   : out uart_byte_t
    );

    procedure tb_recv_uart_response(
        signal rx_serial : in std_logic;
        variable packet  : out uart_response_packet_t
    );

end package tb_uart_mnist_pkg;

package body tb_uart_mnist_pkg is

    function tb_make_payload(seed : natural) return uart_frame_payload_t is
        variable payload_v : uart_frame_payload_t := (others => (others => '0'));
        variable byte_v    : natural;
    begin
        for i in payload_v'range loop
            byte_v := (seed + i * 37 + (i mod 11) * 9) mod 256;
            payload_v(i) := std_logic_vector(to_unsigned(byte_v, 8));
        end loop;

        return payload_v;
    end function;

    function tb_payload_to_image(
        payload : uart_frame_payload_t
    ) return imagem_mnist_t is
        variable image_v : imagem_mnist_t := (others => '0');
        variable base_v  : natural;
    begin
        for i in payload'range loop
            base_v := i * 8;

            for b in 0 to 7 loop
                image_v(base_v + b) := payload(i)(7 - b);
            end loop;
        end loop;

        return image_v;
    end function;

    function tb_packet_checksum(
        cmd     : uart_byte_t;
        len_l   : uart_byte_t;
        len_h   : uart_byte_t;
        seq     : uart_seq_t;
        payload : uart_frame_payload_t
    ) return uart_byte_t is
        variable checksum_v : uart_byte_t;
    begin
        checksum_v := cmd xor len_l xor len_h xor seq;

        for i in payload'range loop
            checksum_v := checksum_v xor payload(i);
        end loop;

        return checksum_v;
    end function;

    function tb_response_checksum(
        cmd        : uart_byte_t;
        seq        : uart_seq_t;
        erro_byte  : uart_byte_t
    ) return uart_byte_t is
    begin
        return cmd xor x"01" xor x"00" xor seq xor erro_byte;
    end function;

    function tb_response_byte(
        indice    : natural;
        cmd       : uart_byte_t;
        seq       : uart_seq_t;
        erro_byte : uart_byte_t
    ) return uart_byte_t is
    begin
        case indice is
            when 0 =>
                return UART_HEADER0_C;
            when 1 =>
                return UART_HEADER1_C;
            when 2 =>
                return cmd;
            when 3 =>
                return x"01";
            when 4 =>
                return x"00";
            when 5 =>
                return seq;
            when 6 =>
                return erro_byte;
            when others =>
                return tb_response_checksum(cmd, seq, erro_byte);
        end case;
    end function;

    procedure tb_wait_cycles(
        signal clock : in std_logic;
        cycles       : in natural
    ) is
    begin
        for i in 1 to cycles loop
            wait until rising_edge(clock);
            wait for 1 ns;
        end loop;
    end procedure;

    procedure tb_apply_reset(
        signal clock : in std_logic;
        signal reset : out std_logic
    ) is
    begin
        reset <= '1';
        tb_wait_cycles(clock, 3);
        reset <= '0';
        tb_wait_cycles(clock, 1);
    end procedure;

    procedure tb_pulse_parallel_byte(
        signal clock       : in std_logic;
        signal byte_rx     : out uart_byte_t;
        signal byte_valido : out std_logic;
        value              : in uart_byte_t
    ) is
    begin
        byte_rx     <= value;
        byte_valido <= '1';
        wait until rising_edge(clock);
        wait for 1 ns;
        byte_valido <= '0';
    end procedure;

    procedure tb_pulse_std_logic(
        signal clock : in std_logic;
        signal value : out std_logic
    ) is
    begin
        value <= '1';
        wait until rising_edge(clock);
        wait for 1 ns;
        value <= '0';
    end procedure;

    procedure tb_expect_one_cycle_high(
        signal clock : in std_logic;
        signal pulse : in std_logic;
        msg          : in string
    ) is
    begin
        assert pulse = '1'
            report msg & ": pulso nao ficou alto"
            severity failure;

        wait until rising_edge(clock);
        wait for 1 ns;

        assert pulse = '0'
            report msg & ": pulso durou mais de um clock"
            severity failure;
    end procedure;

    procedure tb_wait_for_pulse(
        signal clock : in std_logic;
        signal pulse : in std_logic;
        max_cycles   : in natural;
        msg          : in string
    ) is
    begin
        for i in 0 to max_cycles loop
            wait until rising_edge(clock);
            wait for 1 ns;

            if pulse = '1' then
                return;
            end if;
        end loop;

        assert false
            report msg & ": timeout aguardando pulso"
            severity failure;
    end procedure;

    procedure tb_send_uart_byte(
        signal tx_serial : out std_logic;
        value            : in uart_byte_t
    ) is
    begin
        tx_serial <= '0';
        wait for TB_BIT_TIME_C;

        for i in 0 to 7 loop
            tx_serial <= value(i);
            wait for TB_BIT_TIME_C;
        end loop;

        tx_serial <= '1';
        wait for TB_BIT_TIME_C;
    end procedure;

    procedure tb_send_uart_bad_frame(
        signal tx_serial : out std_logic;
        value            : in uart_byte_t
    ) is
    begin
        tx_serial <= '0';
        wait for TB_BIT_TIME_C;

        for i in 0 to 7 loop
            tx_serial <= value(i);
            wait for TB_BIT_TIME_C;
        end loop;

        tx_serial <= '0';
        wait for TB_BIT_TIME_C;
        tx_serial <= '1';
        wait for TB_BIT_TIME_C;
    end procedure;

    procedure tb_send_uart_byte_early_stop(
        signal tx_serial : out std_logic;
        value            : in uart_byte_t
    ) is
    begin
        tx_serial <= '0';
        wait for TB_BIT_TIME_C;

        for i in 0 to 7 loop
            tx_serial <= value(i);
            wait for TB_BIT_TIME_C;
        end loop;

        tx_serial <= '1';
        wait for TB_BIT_TIME_C / 4;
    end procedure;

    procedure tb_send_uart_bad_frame_until_pulse(
        signal tx_serial : out std_logic;
        signal clock     : in std_logic;
        signal pulse     : in std_logic;
        value            : in uart_byte_t;
        max_cycles       : in natural;
        msg              : in string
    ) is
    begin
        tx_serial <= '0';
        wait for TB_BIT_TIME_C;

        for i in 0 to 7 loop
            tx_serial <= value(i);
            wait for TB_BIT_TIME_C;
        end loop;

        tx_serial <= '0';
        tb_wait_for_pulse(clock, pulse, max_cycles, msg);
    end procedure;

    procedure tb_send_uart_frame_packet(
        signal tx_serial : out std_logic;
        seq              : in uart_seq_t;
        payload          : in uart_frame_payload_t;
        checksum_xor     : in uart_byte_t
    ) is
        variable checksum_v : uart_byte_t;
    begin
        checksum_v := tb_packet_checksum(
            UART_CMD_FRAME_C,
            TB_UART_LEN_L_C,
            TB_UART_LEN_H_C,
            seq,
            payload
        ) xor checksum_xor;

        tb_send_uart_byte(tx_serial, UART_HEADER0_C);
        tb_send_uart_byte(tx_serial, UART_HEADER1_C);
        tb_send_uart_byte(tx_serial, UART_CMD_FRAME_C);
        tb_send_uart_byte(tx_serial, TB_UART_LEN_L_C);
        tb_send_uart_byte(tx_serial, TB_UART_LEN_H_C);
        tb_send_uart_byte(tx_serial, seq);

        for i in payload'range loop
            tb_send_uart_byte(tx_serial, payload(i));
        end loop;

        tb_send_uart_byte_early_stop(tx_serial, checksum_v);
    end procedure;

    procedure tb_recv_uart_byte(
        signal rx_serial : in std_logic;
        variable value   : out uart_byte_t
    ) is
    begin
        if rx_serial /= '0' then
            wait until rx_serial = '0';
        end if;

        wait for TB_BIT_TIME_C + TB_BIT_TIME_C / 2;

        for i in 0 to 7 loop
            value(i) := rx_serial;
            wait for TB_BIT_TIME_C;
        end loop;

        assert rx_serial = '1'
            report "stop bit UART nao ficou alto"
            severity failure;

        wait for TB_BIT_TIME_C / 2;
    end procedure;

    procedure tb_recv_uart_response(
        signal rx_serial : in std_logic;
        variable packet  : out uart_response_packet_t
    ) is
    begin
        for i in packet'range loop
            tb_recv_uart_byte(rx_serial, packet(i));
        end loop;
    end procedure;

end package body tb_uart_mnist_pkg;

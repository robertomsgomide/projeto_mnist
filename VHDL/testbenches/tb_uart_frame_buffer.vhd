-------------------------------------------------------------------------------
-- Arquivo   : tb_uart_frame_buffer.vhd
-------------------------------------------------------------------------------
-- Descricao : testbench assertivo para uart_frame_buffer.
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

entity tb_uart_frame_buffer is
end entity tb_uart_frame_buffer;

architecture sim of tb_uart_frame_buffer is

    signal clock : std_logic := '0';
    signal reset : std_logic := '0';

    signal payload_byte   : uart_byte_t := (others => '0');
    signal payload_indice : uart_payload_index_t := (others => '0');
    signal payload_valido : std_logic := '0';

    signal pacote_valido   : std_logic := '0';
    signal pacote_invalido : std_logic := '0';

    signal frame_recebido        : imagem_mnist_t;
    signal frame_recebido_valido : std_logic;

    constant ZERO_IMAGE_C : imagem_mnist_t := (others => '0');

    procedure pulse_payload(
        signal clock_p         : in std_logic;
        signal payload_byte_p  : out uart_byte_t;
        signal payload_index_p : out uart_payload_index_t;
        signal payload_valid_p : out std_logic;
        indice                 : in natural;
        value                  : in uart_byte_t
    ) is
    begin
        payload_index_p <= to_unsigned(indice, payload_index_p'length);
        payload_byte_p  <= value;
        payload_valid_p <= '1';
        wait until rising_edge(clock_p);
        wait for 1 ns;
        payload_valid_p <= '0';
    end procedure;

begin

    clock <= not clock after TB_CLK_PERIOD_C / 2;

    dut : entity work.uart_frame_buffer
        port map (
            clock                  => clock,
            reset                  => reset,
            payload_byte           => payload_byte,
            payload_indice         => payload_indice,
            payload_valido         => payload_valido,
            pacote_valido          => pacote_valido,
            pacote_invalido        => pacote_invalido,
            frame_recebido         => frame_recebido,
            frame_recebido_valido  => frame_recebido_valido
        );

    stim : process
        variable payload_v        : uart_frame_payload_t := tb_make_payload(43);
        variable expected_image_v : imagem_mnist_t;
        variable single_byte_v    : uart_frame_payload_t := (others => (others => '0'));
    begin
        tb_apply_reset(clock, reset);

        assert frame_recebido = ZERO_IMAGE_C
            report "reset nao limpou frame_recebido"
            severity failure;
        assert frame_recebido_valido = '0'
            report "reset deixou frame_recebido_valido alto"
            severity failure;

        expected_image_v := tb_payload_to_image(payload_v);

        for i in payload_v'range loop
            pulse_payload(clock, payload_byte, payload_indice, payload_valido, i, payload_v(i));
            assert frame_recebido_valido = '0'
                report "frame ficou valido antes de pacote_valido"
                severity failure;
        end loop;

        pacote_valido <= '1';
        wait until rising_edge(clock);
        wait for 1 ns;
        pacote_valido <= '0';

        assert frame_recebido_valido = '1'
            report "pacote_valido nao gerou frame_recebido_valido"
            severity failure;
        assert frame_recebido = expected_image_v
            report "conversao de payload para imagem divergente"
            severity failure;

        tb_expect_one_cycle_high(clock, frame_recebido_valido, "frame_recebido_valido");

        pulse_payload(clock, payload_byte, payload_indice, payload_valido, 12, x"FF");
        pulse_payload(clock, payload_byte, payload_indice, payload_valido, 0, x"80");

        pacote_valido <= '1';
        wait until rising_edge(clock);
        wait for 1 ns;
        pacote_valido <= '0';

        single_byte_v := (others => (others => '0'));
        single_byte_v(0) := x"80";
        assert frame_recebido_valido = '1'
            report "nova imagem a partir do indice zero nao ficou valida"
            severity failure;
        assert frame_recebido = tb_payload_to_image(single_byte_v)
            report "payload no indice zero nao reiniciou a imagem em montagem"
            severity failure;
        tb_expect_one_cycle_high(clock, frame_recebido_valido, "reinicio por indice zero valido");

        pulse_payload(clock, payload_byte, payload_indice, payload_valido, 0, x"FF");
        pacote_invalido <= '1';
        wait until rising_edge(clock);
        wait for 1 ns;
        pacote_invalido <= '0';
        assert frame_recebido_valido = '0'
            report "pacote invalido gerou frame_recebido_valido"
            severity failure;

        pacote_valido <= '1';
        wait until rising_edge(clock);
        wait for 1 ns;
        pacote_valido <= '0';
        assert frame_recebido_valido = '1'
            report "pulso valido apos invalido nao emitiu frame limpo"
            severity failure;
        assert frame_recebido = ZERO_IMAGE_C
            report "pacote invalido nao limpou imagem em montagem"
            severity failure;
        tb_expect_one_cycle_high(clock, frame_recebido_valido, "frame limpo valido");

        payload_byte     <= x"FF";
        payload_indice   <= (others => '0');
        payload_valido   <= '1';
        pacote_valido    <= '1';
        pacote_invalido  <= '1';
        wait until rising_edge(clock);
        wait for 1 ns;
        payload_valido  <= '0';
        pacote_valido   <= '0';
        pacote_invalido <= '0';
        assert frame_recebido_valido = '0'
            report "prioridade de pacote_invalido violada"
            severity failure;

        pacote_valido <= '1';
        wait until rising_edge(clock);
        wait for 1 ns;
        pacote_valido <= '0';
        assert frame_recebido = ZERO_IMAGE_C
            report "prioridade de pacote_invalido permitiu escrita de payload"
            severity failure;
        tb_expect_one_cycle_high(clock, frame_recebido_valido, "frame limpo por prioridade valido");

        payload_byte    <= x"80";
        payload_indice  <= (others => '0');
        payload_valido  <= '1';
        pacote_valido   <= '1';
        wait until rising_edge(clock);
        wait for 1 ns;
        payload_valido <= '0';
        pacote_valido  <= '0';
        assert frame_recebido_valido = '0'
            report "prioridade de payload_valido sobre pacote_valido violada"
            severity failure;

        pacote_valido <= '1';
        wait until rising_edge(clock);
        wait for 1 ns;
        pacote_valido <= '0';
        single_byte_v := (others => (others => '0'));
        single_byte_v(0) := x"80";
        assert frame_recebido = tb_payload_to_image(single_byte_v)
            report "prioridade do payload nao salvou byte para proximo pulso valido"
            severity failure;
        tb_expect_one_cycle_high(clock, frame_recebido_valido, "prioridade do payload valida");

        report "tb_uart_frame_buffer concluido" severity note;
        stop;
    end process;

end architecture sim;

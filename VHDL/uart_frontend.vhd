-------------------------------------------------------------------------------
-- Arquivo   : uart_frontend.vhd
-------------------------------------------------------------------------------
-- Descricao : bloco de interface serial do projeto. Integra receptor UART,
--             transmissor UART, interpretador de pacotes, gerador de ACK/NACK
--             e buffer de frame recebido do ESP32.
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     18/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  versao inicial
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;

entity uart_frontend is
    port (
        clock : in std_logic;
        reset : in std_logic;

        uart_rx_serial : in  std_logic;
        uart_tx_serial : out std_logic;

        frame_recebido        : out imagem_mnist_t;
        frame_recebido_valido : out std_logic;

        uart_recebendo    : out std_logic;
        pacote_ok_pulso   : out std_logic;
        pacote_erro_pulso : out std_logic;
        erro_codigo       : out uart_erro_t;

        seq_ultimo : out uart_seq_t
    );
end entity uart_frontend;

architecture arch of uart_frontend is

    component uart_rx is
        port (
            clock : in std_logic;
            reset : in std_logic;

            rx_serial : in std_logic;

            byte_rx     : out uart_byte_t;
            byte_valido : out std_logic;
            erro_frame  : out std_logic;
            recebendo   : out std_logic
        );
    end component;

    component uart_tx is
        port (
            clock : in std_logic;
            reset : in std_logic;

            byte_tx      : in uart_byte_t;
            inicia_envio : in std_logic;

            tx_serial : out std_logic;
            ocupado   : out std_logic;
            pronto    : out std_logic
        );
    end component;

    component uart_packet_rx is
        port (
            clock : in std_logic;
            reset : in std_logic;

            byte_rx     : in uart_byte_t;
            byte_valido : in std_logic;
            erro_frame  : in std_logic;

            payload_byte   : out uart_byte_t;
            payload_indice : out uart_payload_index_t;
            payload_valido : out std_logic;

            cmd_rx      : out uart_byte_t;
            seq_rx      : out uart_seq_t;
            payload_len : out uart_len_t;

            pacote_valido   : out std_logic;
            pacote_invalido : out std_logic;
            erro_codigo     : out uart_erro_t;
            ocupado         : out std_logic
        );
    end component;

    component uart_packet_tx_ack is
        port (
            clock : in std_logic;
            reset : in std_logic;

            solicita_ack  : in std_logic;
            solicita_nack : in std_logic;

            seq_rx      : in uart_seq_t;
            erro_codigo : in uart_erro_t;

            tx_ocupado : in std_logic;

            byte_tx      : out uart_byte_t;
            inicia_envio : out std_logic;

            ocupado : out std_logic
        );
    end component;

    component uart_frame_buffer is
        port (
            clock : in std_logic;
            reset : in std_logic;

            payload_byte   : in uart_byte_t;
            payload_indice : in uart_payload_index_t;
            payload_valido : in std_logic;

            pacote_valido   : in std_logic;
            pacote_invalido : in std_logic;

            frame_recebido        : out imagem_mnist_t;
            frame_recebido_valido : out std_logic
        );
    end component;

    signal byte_rx_s       : uart_byte_t := (others => '0');
    signal byte_valido_s   : std_logic := '0';
    signal erro_frame_s    : std_logic := '0';
    signal rx_recebendo_s  : std_logic := '0';

    signal payload_byte_s   : uart_byte_t := (others => '0');
    signal payload_indice_s : uart_payload_index_t := (others => '0');
    signal payload_valido_s : std_logic := '0';

    signal cmd_rx_s      : uart_byte_t := (others => '0');
    signal seq_rx_s      : uart_seq_t := (others => '0');
    signal payload_len_s : uart_len_t := (others => '0');

    signal pacote_valido_s   : std_logic := '0';
    signal pacote_invalido_s : std_logic := '0';
    signal erro_packet_s     : uart_erro_t := UART_ERRO_NENHUM_C;
    signal packet_ocupado_s  : std_logic := '0';

    signal byte_tx_s      : uart_byte_t := (others => '0');
    signal inicia_tx_s    : std_logic := '0';
    signal tx_ocupado_s   : std_logic := '0';
    signal tx_pronto_s    : std_logic := '0';
    signal ack_ocupado_s  : std_logic := '0';

    signal erro_codigo_s : uart_erro_t := UART_ERRO_NENHUM_C;

begin

    u_uart_rx : uart_rx
        port map (
            clock       => clock,
            reset       => reset,
            rx_serial   => uart_rx_serial,
            byte_rx     => byte_rx_s,
            byte_valido => byte_valido_s,
            erro_frame  => erro_frame_s,
            recebendo   => rx_recebendo_s
        );

    u_packet_rx : uart_packet_rx
        port map (
            clock           => clock,
            reset           => reset,
            byte_rx         => byte_rx_s,
            byte_valido     => byte_valido_s,
            erro_frame      => erro_frame_s,
            payload_byte    => payload_byte_s,
            payload_indice  => payload_indice_s,
            payload_valido  => payload_valido_s,
            cmd_rx          => cmd_rx_s,
            seq_rx          => seq_rx_s,
            payload_len     => payload_len_s,
            pacote_valido   => pacote_valido_s,
            pacote_invalido => pacote_invalido_s,
            erro_codigo     => erro_packet_s,
            ocupado         => packet_ocupado_s
        );

    u_frame_buffer : uart_frame_buffer
        port map (
            clock                  => clock,
            reset                  => reset,
            payload_byte           => payload_byte_s,
            payload_indice         => payload_indice_s,
            payload_valido         => payload_valido_s,
            pacote_valido          => pacote_valido_s,
            pacote_invalido        => pacote_invalido_s,
            frame_recebido         => frame_recebido,
            frame_recebido_valido  => frame_recebido_valido
        );

    u_tx_ack : uart_packet_tx_ack
        port map (
            clock          => clock,
            reset          => reset,
            solicita_ack   => pacote_valido_s,
            solicita_nack  => pacote_invalido_s,
            seq_rx         => seq_rx_s,
            erro_codigo    => erro_packet_s,
            tx_ocupado     => tx_ocupado_s,
            byte_tx        => byte_tx_s,
            inicia_envio   => inicia_tx_s,
            ocupado        => ack_ocupado_s
        );

    u_uart_tx : uart_tx
        port map (
            clock         => clock,
            reset         => reset,
            byte_tx       => byte_tx_s,
            inicia_envio  => inicia_tx_s,
            tx_serial     => uart_tx_serial,
            ocupado       => tx_ocupado_s,
            pronto        => tx_pronto_s
        );

    process(clock, reset)
    begin
        if reset = '1' then
            erro_codigo_s <= UART_ERRO_NENHUM_C;

        elsif rising_edge(clock) then
            if pacote_invalido_s = '1' then
                erro_codigo_s <= erro_packet_s;

            elsif erro_frame_s = '1' and packet_ocupado_s = '0' then
                erro_codigo_s <= UART_ERRO_FRAME_C;

            elsif pacote_valido_s = '1' then
                erro_codigo_s <= UART_ERRO_NENHUM_C;
            end if;
        end if;
    end process;

    uart_recebendo <= rx_recebendo_s or packet_ocupado_s or ack_ocupado_s;

    pacote_ok_pulso <= pacote_valido_s;

    pacote_erro_pulso <= pacote_invalido_s or
                         (erro_frame_s and not packet_ocupado_s);

    erro_codigo <= erro_codigo_s;
    seq_ultimo  <= seq_rx_s;

end architecture arch;

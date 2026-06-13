-------------------------------------------------------------------------------
-- Arquivo   : uart_packet_tx_ack.vhd
-------------------------------------------------------------------------------
-- Descricao : gerador de respostas UART para o ESP32. Emite ACK/NACK e codigos
--             simples de status apos a recepcao de pacotes validos ou invalidos.
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     18/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  versao inicial
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;

entity uart_packet_tx_ack is
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
end entity uart_packet_tx_ack;

architecture arch of uart_packet_tx_ack is

    constant ACK_LEN_L_C : uart_byte_t := x"01";
    constant ACK_LEN_H_C : uart_byte_t := x"00";
    constant ACK_BYTES_C : natural := 8;

    type estado_t is (
        S_IDLE,
        S_PREPARA,
        S_PULSO,
        S_AGUARDA_OCUPA,
        S_AGUARDA_LIVRE
    );

    signal estado : estado_t := S_IDLE;

    signal indice_s : natural range 0 to ACK_BYTES_C-1 := 0;
    signal cmd_s    : uart_byte_t := UART_CMD_ACK_C;
    signal seq_s    : uart_seq_t  := (others => '0');
    signal erro_s   : uart_byte_t := (others => '0');

    signal byte_tx_s      : uart_byte_t := (others => '0');
    signal inicia_envio_s : std_logic := '0';

    function checksum_ack(
        cmd_f  : uart_byte_t;
        seq_f  : uart_seq_t;
        erro_f : uart_byte_t
    ) return uart_byte_t is
        variable soma_v : uart_byte_t;
    begin
        soma_v := cmd_f xor ACK_LEN_L_C xor ACK_LEN_H_C xor seq_f xor erro_f;
        return soma_v;
    end function;

    function byte_ack(
        indice_f : natural;
        cmd_f    : uart_byte_t;
        seq_f    : uart_seq_t;
        erro_f   : uart_byte_t
    ) return uart_byte_t is
        variable byte_v : uart_byte_t;
    begin
        case indice_f is
            when 0 =>
                byte_v := UART_HEADER0_C;
            when 1 =>
                byte_v := UART_HEADER1_C;
            when 2 =>
                byte_v := cmd_f;
            when 3 =>
                byte_v := ACK_LEN_L_C;
            when 4 =>
                byte_v := ACK_LEN_H_C;
            when 5 =>
                byte_v := seq_f;
            when 6 =>
                byte_v := erro_f;
            when others =>
                byte_v := checksum_ack(cmd_f, seq_f, erro_f);
        end case;

        return byte_v;
    end function;

begin

    process(clock, reset)
    begin
        if reset = '1' then
            estado          <= S_IDLE;
            indice_s        <= 0;
            cmd_s           <= UART_CMD_ACK_C;
            seq_s           <= (others => '0');
            erro_s          <= (others => '0');
            byte_tx_s       <= (others => '0');
            inicia_envio_s  <= '0';

        elsif rising_edge(clock) then
            inicia_envio_s <= '0';

            case estado is
                when S_IDLE =>
                    indice_s <= 0;

                    if solicita_nack = '1' then
                        cmd_s  <= UART_CMD_NACK_C;
                        seq_s  <= seq_rx;
                        erro_s <= "0000" & erro_codigo;
                        estado <= S_PREPARA;

                    elsif solicita_ack = '1' then
                        cmd_s  <= UART_CMD_ACK_C;
                        seq_s  <= seq_rx;
                        erro_s <= (others => '0');
                        estado <= S_PREPARA;
                    end if;

                when S_PREPARA =>
                    if tx_ocupado = '0' then
                        byte_tx_s      <= byte_ack(indice_s, cmd_s, seq_s, erro_s);
                        inicia_envio_s <= '1';
                        estado         <= S_PULSO;
                    end if;

                when S_PULSO =>
                    estado <= S_AGUARDA_OCUPA;

                when S_AGUARDA_OCUPA =>
                    if tx_ocupado = '1' then
                        estado <= S_AGUARDA_LIVRE;
                    end if;

                when S_AGUARDA_LIVRE =>
                    if tx_ocupado = '0' then
                        if indice_s = ACK_BYTES_C-1 then
                            estado <= S_IDLE;
                        else
                            indice_s <= indice_s + 1;
                            estado   <= S_PREPARA;
                        end if;
                    end if;
            end case;
        end if;
    end process;

    byte_tx      <= byte_tx_s;
    inicia_envio <= inicia_envio_s;
    ocupado      <= '1' when estado /= S_IDLE else '0';

end architecture arch;

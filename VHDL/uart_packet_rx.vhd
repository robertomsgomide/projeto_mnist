-------------------------------------------------------------------------------
-- Arquivo   : uart_packet_rx.vhd
-------------------------------------------------------------------------------
-- Descricao : interpretador de pacotes recebidos pela UART. Valida cabecalho,
--             comando, tamanho, payload e checksum antes de liberar o frame
--             28x28 para o restante do sistema.
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     18/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  versao inicial
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;

entity uart_packet_rx is
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
end entity uart_packet_rx;

architecture arch of uart_packet_rx is

    constant UART_LEN_FRAME_C : uart_len_t :=
        to_unsigned(UART_PAYLOAD_FRAME_BYTES_C, uart_len_t'length);

    type estado_t is (
        S_HEADER0,
        S_HEADER1,
        S_CMD,
        S_LEN_L,
        S_LEN_H,
        S_SEQ,
        S_PAYLOAD,
        S_CHECKSUM
    );

    signal estado : estado_t := S_HEADER0;

    signal checksum_s : uart_byte_t := (others => '0');
    signal cmd_s      : uart_byte_t := (others => '0');
    signal seq_s      : uart_seq_t  := (others => '0');
    signal len_s      : uart_len_t  := (others => '0');
    signal len_l_s    : uart_byte_t := (others => '0');

    signal seq_recebida_s : std_logic := '0';

    signal indice_payload_s : uart_payload_index_t := (others => '0');

    signal payload_byte_s   : uart_byte_t := (others => '0');
    signal payload_indice_s : uart_payload_index_t := (others => '0');
    signal payload_valido_s : std_logic := '0';

    signal pacote_valido_s   : std_logic := '0';
    signal pacote_invalido_s : std_logic := '0';
    signal erro_codigo_s     : uart_erro_t := UART_ERRO_NENHUM_C;

    procedure aborta_pacote(
        signal estado_p             : out estado_t;
        signal pacote_invalido_p    : out std_logic;
        signal erro_codigo_p        : out uart_erro_t;
        signal checksum_p           : out uart_byte_t;
        signal indice_payload_p     : out uart_payload_index_t;
        signal seq_recebida_p       : out std_logic;
        signal seq_p                : out uart_seq_t;
        constant codigo_p           : in  uart_erro_t;
        constant preserva_seq_p     : in  boolean
    ) is
    begin
        pacote_invalido_p <= '1';
        erro_codigo_p     <= codigo_p;

        estado_p         <= S_HEADER0;
        checksum_p       <= (others => '0');
        indice_payload_p <= (others => '0');
        seq_recebida_p   <= '0';

        if not preserva_seq_p then
            seq_p <= (others => '0');
        end if;
    end procedure;

begin

    process(clock, reset)
        variable len_tmp_v : uart_len_t;
    begin
        if reset = '1' then
            estado             <= S_HEADER0;
            checksum_s         <= (others => '0');
            cmd_s              <= (others => '0');
            seq_s              <= (others => '0');
            len_s              <= (others => '0');
            len_l_s            <= (others => '0');
            seq_recebida_s     <= '0';
            indice_payload_s   <= (others => '0');
            payload_byte_s     <= (others => '0');
            payload_indice_s   <= (others => '0');
            payload_valido_s   <= '0';
            pacote_valido_s    <= '0';
            pacote_invalido_s  <= '0';
            erro_codigo_s      <= UART_ERRO_NENHUM_C;

        elsif rising_edge(clock) then
            payload_valido_s  <= '0';
            pacote_valido_s   <= '0';
            pacote_invalido_s <= '0';

            ----------------------------------------------------------------
            -- Um erro de frame no meio de um pacote invalida o pacote atual.
            -- Se o erro ocorreu antes de SEQ, a resposta nao deve reutilizar
            -- uma sequencia antiga.
            ----------------------------------------------------------------
            if erro_frame = '1' then
                if estado /= S_HEADER0 then
                    aborta_pacote(
                        estado,
                        pacote_invalido_s,
                        erro_codigo_s,
                        checksum_s,
                        indice_payload_s,
                        seq_recebida_s,
                        seq_s,
                        UART_ERRO_FRAME_C,
                        seq_recebida_s = '1'
                    );
                else
                    erro_codigo_s  <= UART_ERRO_FRAME_C;
                    seq_s          <= (others => '0');
                    seq_recebida_s <= '0';
                end if;

            elsif byte_valido = '1' then
                case estado is
                    when S_HEADER0 =>
                        if byte_rx = UART_HEADER0_C then
                            estado           <= S_HEADER1;
                            checksum_s       <= (others => '0');
                            cmd_s            <= (others => '0');
                            seq_s            <= (others => '0');
                            len_s            <= (others => '0');
                            len_l_s          <= (others => '0');
                            seq_recebida_s   <= '0';
                            indice_payload_s <= (others => '0');
                        end if;

                    when S_HEADER1 =>
                        if byte_rx = UART_HEADER1_C then
                            estado <= S_CMD;

                        elsif byte_rx = UART_HEADER0_C then
                            estado           <= S_HEADER1;
                            checksum_s       <= (others => '0');
                            cmd_s            <= (others => '0');
                            seq_s            <= (others => '0');
                            len_s            <= (others => '0');
                            len_l_s          <= (others => '0');
                            seq_recebida_s   <= '0';
                            indice_payload_s <= (others => '0');

                        else
                            aborta_pacote(
                                estado,
                                pacote_invalido_s,
                                erro_codigo_s,
                                checksum_s,
                                indice_payload_s,
                                seq_recebida_s,
                                seq_s,
                                UART_ERRO_HEADER_C,
                                false
                            );
                        end if;

                    when S_CMD =>
                        cmd_s      <= byte_rx;
                        checksum_s <= byte_rx;

                        if byte_rx = UART_CMD_FRAME_C then
                            estado <= S_LEN_L;
                        else
                            aborta_pacote(
                                estado,
                                pacote_invalido_s,
                                erro_codigo_s,
                                checksum_s,
                                indice_payload_s,
                                seq_recebida_s,
                                seq_s,
                                UART_ERRO_COMANDO_C,
                                false
                            );
                        end if;

                    when S_LEN_L =>
                        len_l_s    <= byte_rx;
                        checksum_s <= checksum_s xor byte_rx;
                        estado     <= S_LEN_H;

                    when S_LEN_H =>
                        len_tmp_v  := unsigned(byte_rx & len_l_s);
                        len_s      <= len_tmp_v;
                        checksum_s <= checksum_s xor byte_rx;

                        if len_tmp_v = UART_LEN_FRAME_C then
                            estado <= S_SEQ;
                        else
                            aborta_pacote(
                                estado,
                                pacote_invalido_s,
                                erro_codigo_s,
                                checksum_s,
                                indice_payload_s,
                                seq_recebida_s,
                                seq_s,
                                UART_ERRO_TAMANHO_C,
                                false
                            );
                        end if;

                    when S_SEQ =>
                        seq_s            <= byte_rx;
                        seq_recebida_s   <= '1';
                        checksum_s       <= checksum_s xor byte_rx;
                        indice_payload_s <= (others => '0');
                        estado           <= S_PAYLOAD;

                    when S_PAYLOAD =>
                        payload_byte_s     <= byte_rx;
                        payload_indice_s   <= indice_payload_s;
                        payload_valido_s   <= '1';
                        checksum_s         <= checksum_s xor byte_rx;

                        if indice_payload_s =
                           to_unsigned(UART_PAYLOAD_FRAME_BYTES_C - 1,
                                       indice_payload_s'length) then
                            estado <= S_CHECKSUM;
                        else
                            indice_payload_s <= indice_payload_s + 1;
                        end if;

                    when S_CHECKSUM =>
                        if byte_rx = checksum_s then
                            pacote_valido_s <= '1';
                            erro_codigo_s   <= UART_ERRO_NENHUM_C;
                        else
                            pacote_invalido_s <= '1';
                            erro_codigo_s     <= UART_ERRO_CHECKSUM_C;
                        end if;

                        estado           <= S_HEADER0;
                        checksum_s       <= (others => '0');
                        indice_payload_s <= (others => '0');
                        seq_recebida_s   <= '0';
                end case;
            end if;
        end if;
    end process;

    payload_byte   <= payload_byte_s;
    payload_indice <= payload_indice_s;
    payload_valido <= payload_valido_s;

    cmd_rx      <= cmd_s;
    seq_rx      <= seq_s;
    payload_len <= len_s;

    pacote_valido   <= pacote_valido_s;
    pacote_invalido <= pacote_invalido_s;
    erro_codigo     <= erro_codigo_s;
    ocupado         <= '1' when estado /= S_HEADER0 else '0';

end architecture arch;

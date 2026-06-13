-------------------------------------------------------------------------------
-- Arquivo   : uart_frame_buffer.vhd
-------------------------------------------------------------------------------
-- Descricao : recebe bytes de payload validados pela UART, remonta um frame
--             completo 28x28 e entrega esse frame ao mnist_canvas.
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     18/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  versao inicial
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;

entity uart_frame_buffer is
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
end entity uart_frame_buffer;

architecture arch of uart_frame_buffer is

    signal frame_trabalho_s : imagem_mnist_t := (others => '0');
    signal frame_saida_s    : imagem_mnist_t := (others => '0');
    signal frame_valido_s   : std_logic := '0';

begin

    process(clock, reset)
        variable imagem_v : imagem_mnist_t;
        variable base_v   : natural range 0 to IMG_BITS_C-1;
    begin
        if reset = '1' then
            frame_trabalho_s <= (others => '0');
            frame_saida_s    <= (others => '0');
            frame_valido_s   <= '0';

        elsif rising_edge(clock) then
            frame_valido_s <= '0';

            if pacote_invalido = '1' then
                frame_trabalho_s <= (others => '0');

            elsif payload_valido = '1' then
                if payload_indice = to_unsigned(0, payload_indice'length) then
                    imagem_v := (others => '0');
                else
                    imagem_v := frame_trabalho_s;
                end if;

                base_v := to_integer(payload_indice) * 8;

                for b in 0 to 7 loop
                    imagem_v(base_v + b) := payload_byte(7-b);
                end loop;

                frame_trabalho_s <= imagem_v;

            elsif pacote_valido = '1' then
                frame_saida_s  <= frame_trabalho_s;
                frame_valido_s <= '1';
            end if;
        end if;
    end process;

    frame_recebido        <= frame_saida_s;
    frame_recebido_valido <= frame_valido_s;

end architecture arch;

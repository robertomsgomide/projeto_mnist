-------------------------------------------------------------------------------
-- Arquivo   : uart_tx.vhd
-------------------------------------------------------------------------------
-- Descricao : transmissor UART 8N1 parametrizavel. Envia bytes paralelos pela
--             linha serial, permitindo respostas simples da FPGA ao ESP32.
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     18/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  versao inicial
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;

entity uart_tx is
    port (
        clock : in std_logic;
        reset : in std_logic;

        byte_tx      : in uart_byte_t;
        inicia_envio : in std_logic;

        tx_serial : out std_logic;
        ocupado   : out std_logic;
        pronto    : out std_logic
    );
end entity uart_tx;

architecture arch of uart_tx is

    constant BAUD_DIV_C : positive := CLOCK_FREQ_HZ_C / UART_BAUD_C;

    type estado_t is (
        S_IDLE,
        S_START,
        S_DATA,
        S_STOP
    );

    signal estado : estado_t := S_IDLE;

    signal contador_baud_s : natural range 0 to BAUD_DIV_C-1 := 0;
    signal indice_bit_s    : natural range 0 to 7 := 0;
    signal deslocador_s    : uart_byte_t := (others => '0');
    signal tx_reg_s        : std_logic := '1';

begin

    process(clock, reset)
    begin
        if reset = '1' then
            estado          <= S_IDLE;
            contador_baud_s <= 0;
            indice_bit_s    <= 0;
            deslocador_s    <= (others => '0');
            tx_reg_s        <= '1';

        elsif rising_edge(clock) then
            case estado is
                when S_IDLE =>
                    tx_reg_s        <= '1';
                    contador_baud_s <= 0;
                    indice_bit_s    <= 0;

                    if inicia_envio = '1' then
                        deslocador_s    <= byte_tx;
                        contador_baud_s <= BAUD_DIV_C-1;
                        tx_reg_s        <= '0';
                        estado          <= S_START;
                    end if;

                when S_START =>
                    tx_reg_s <= '0';

                    if contador_baud_s = 0 then
                        contador_baud_s <= BAUD_DIV_C-1;
                        tx_reg_s        <= deslocador_s(0);
                        indice_bit_s    <= 0;
                        estado          <= S_DATA;
                    else
                        contador_baud_s <= contador_baud_s - 1;
                    end if;

                when S_DATA =>
                    tx_reg_s <= deslocador_s(indice_bit_s);

                    if contador_baud_s = 0 then
                        contador_baud_s <= BAUD_DIV_C-1;

                        if indice_bit_s = 7 then
                            tx_reg_s <= '1';
                            estado   <= S_STOP;
                        else
                            indice_bit_s <= indice_bit_s + 1;
                            tx_reg_s     <= deslocador_s(indice_bit_s + 1);
                        end if;
                    else
                        contador_baud_s <= contador_baud_s - 1;
                    end if;

                when S_STOP =>
                    tx_reg_s <= '1';

                    if contador_baud_s = 0 then
                        estado <= S_IDLE;
                    else
                        contador_baud_s <= contador_baud_s - 1;
                    end if;
            end case;
        end if;
    end process;

    tx_serial <= tx_reg_s;
    ocupado   <= '1' when estado /= S_IDLE else '0';
    pronto    <= '1' when estado = S_IDLE else '0';

end architecture arch;

-------------------------------------------------------------------------------
-- Arquivo   : uart_rx.vhd
-------------------------------------------------------------------------------
-- Descricao : receptor UART 8N1 parametrizavel. Converte o sinal serial de
--             entrada em bytes paralelos e gera um pulso de validade para cada
--             byte recebido corretamente.
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     18/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  versao inicial
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;

entity uart_rx is
    port (
        clock : in std_logic;
        reset : in std_logic;

        rx_serial : in std_logic;

        byte_rx     : out uart_byte_t;
        byte_valido : out std_logic;
        erro_frame  : out std_logic;
        recebendo   : out std_logic
    );
end entity uart_rx;

architecture arch of uart_rx is

    constant BAUD_DIV_C  : positive := CLOCK_FREQ_HZ_C / UART_BAUD_C;
    constant MEIO_BIT_C  : natural  := BAUD_DIV_C / 2;

    type estado_t is (
        S_IDLE,
        S_START,
        S_DATA,
        S_STOP
    );

    signal estado : estado_t := S_IDLE;

    signal rx_meta_s : std_logic := '1';
    signal rx_sinc_s : std_logic := '1';

    signal contador_baud_s : natural range 0 to BAUD_DIV_C-1 := 0;
    signal indice_bit_s    : natural range 0 to 7 := 0;
    signal deslocador_s    : uart_byte_t := (others => '0');

    signal byte_reg_s         : uart_byte_t := (others => '0');
    signal byte_valido_reg_s  : std_logic := '0';
    signal erro_frame_reg_s   : std_logic := '0';

begin

    process(clock, reset)
    begin
        if reset = '1' then
            rx_meta_s <= '1';
            rx_sinc_s <= '1';

        elsif rising_edge(clock) then
            rx_meta_s <= rx_serial;
            rx_sinc_s <= rx_meta_s;
        end if;
    end process;

    process(clock, reset)
    begin
        if reset = '1' then
            estado             <= S_IDLE;
            contador_baud_s    <= 0;
            indice_bit_s       <= 0;
            deslocador_s       <= (others => '0');
            byte_reg_s         <= (others => '0');
            byte_valido_reg_s  <= '0';
            erro_frame_reg_s   <= '0';

        elsif rising_edge(clock) then
            byte_valido_reg_s <= '0';
            erro_frame_reg_s  <= '0';

            case estado is
                when S_IDLE =>
                    contador_baud_s <= 0;
                    indice_bit_s    <= 0;

                    if rx_sinc_s = '0' then
                        contador_baud_s <= MEIO_BIT_C;
                        estado          <= S_START;
                    end if;

                when S_START =>
                    if contador_baud_s = 0 then
                        if rx_sinc_s = '0' then
                            contador_baud_s <= BAUD_DIV_C-1;
                            indice_bit_s    <= 0;
                            estado          <= S_DATA;
                        else
                            erro_frame_reg_s <= '1';
                            estado           <= S_IDLE;
                        end if;
                    else
                        contador_baud_s <= contador_baud_s - 1;
                    end if;

                when S_DATA =>
                    if contador_baud_s = 0 then
                        deslocador_s(indice_bit_s) <= rx_sinc_s;
                        contador_baud_s            <= BAUD_DIV_C-1;

                        if indice_bit_s = 7 then
                            estado <= S_STOP;
                        else
                            indice_bit_s <= indice_bit_s + 1;
                        end if;
                    else
                        contador_baud_s <= contador_baud_s - 1;
                    end if;

                when S_STOP =>
                    if contador_baud_s = 0 then
                        if rx_sinc_s = '1' then
                            byte_reg_s        <= deslocador_s;
                            byte_valido_reg_s <= '1';
                        else
                            erro_frame_reg_s <= '1';
                        end if;

                        estado <= S_IDLE;
                    else
                        contador_baud_s <= contador_baud_s - 1;
                    end if;
            end case;
        end if;
    end process;

    byte_rx     <= byte_reg_s;
    byte_valido <= byte_valido_reg_s;
    erro_frame  <= erro_frame_reg_s;
    recebendo   <= '1' when estado /= S_IDLE else '0';

end architecture arch;

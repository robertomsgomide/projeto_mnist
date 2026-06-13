-------------------------------------------------------------------------------
-- Arquivo   : leds_ctrl.vhd
-------------------------------------------------------------------------------
-- Descricao : controlador dos LEDs de interacao. Pisca ao limpar o canvas,
--             percorre um LED no estado de aguarda e mantem os
--             LEDs apagados nos demais casos.
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     18/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  versao inicial
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;

entity leds_ctrl is
    generic (
        CICLO_LED_TICKS_G : positive := CLOCK_FREQ_HZ_C / 10;
        FLASH_LED_TICKS_G : positive := CLOCK_FREQ_HZ_C / 2
    );
    port (
        clock : in std_logic;
        reset : in std_logic;

        limpa_canvas_pulso : in std_logic;

        aguarda : in std_logic;

        ledr : out led_bus_t
    );
end entity leds_ctrl;

architecture arch of leds_ctrl is

    signal ciclo_cont_s : natural range 0 to CICLO_LED_TICKS_G-1 := 0;
    signal ciclo_pos_s  : natural range 0 to LED_COUNT_C-1 := LED_COUNT_C-1;

    signal flash_ativo_s : std_logic := '0';
    signal flash_cont_s  : natural range 0 to FLASH_LED_TICKS_G-1 := 0;

    signal ledr_ciclo_s : led_bus_t := (others => '0');

begin

    process(clock, reset)
    begin
        if reset = '1' then
            ciclo_cont_s  <= 0;
            ciclo_pos_s   <= LED_COUNT_C-1;
            flash_ativo_s <= '0';
            flash_cont_s  <= 0;

        elsif rising_edge(clock) then
            if limpa_canvas_pulso = '1' then
                flash_ativo_s <= '1';
                flash_cont_s  <= 0;

            elsif flash_ativo_s = '1' then
                if flash_cont_s = FLASH_LED_TICKS_G-1 then
                    flash_ativo_s <= '0';
                    flash_cont_s  <= 0;
                else
                    flash_cont_s <= flash_cont_s + 1;
                end if;
            end if;

            if aguarda = '1' then
                if ciclo_cont_s = CICLO_LED_TICKS_G-1 then
                    ciclo_cont_s <= 0;

                    if ciclo_pos_s = 0 then
                        ciclo_pos_s <= LED_COUNT_C-1;
                    else
                        ciclo_pos_s <= ciclo_pos_s - 1;
                    end if;
                else
                    ciclo_cont_s <= ciclo_cont_s + 1;
                end if;
            else
                ciclo_cont_s <= 0;
                ciclo_pos_s  <= LED_COUNT_C-1;
            end if;
        end if;
    end process;

    process(ciclo_pos_s)
    begin
        ledr_ciclo_s <= (others => '0');
        ledr_ciclo_s(ciclo_pos_s) <= '1';
    end process;

    ledr <= (others => '1') when flash_ativo_s = '1' else
            ledr_ciclo_s when aguarda = '1' else
            (others => '0');

end architecture arch;

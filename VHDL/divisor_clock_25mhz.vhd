-------------------------------------------------------------------------------
-- Arquivo   : divisor_clock_25mhz.vhd
-------------------------------------------------------------------------------
-- Descricao : gera um pulso de habilitacao de pixel a 25 MHz a partir de 50 MHz
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     18/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  novo componente
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;

entity divisor_clock_25mhz is
    port (
        clock_50 : in std_logic;
        reset    : in std_logic;

        pixel_tick_25 : out std_logic
    );
end entity divisor_clock_25mhz;

architecture arch of divisor_clock_25mhz is
    signal tick_reg : std_logic := '0';
begin
    process(clock_50, reset)
    begin
        if reset = '1' then
            tick_reg <= '0';
        elsif rising_edge(clock_50) then
            tick_reg <= not tick_reg;
        end if;
    end process;

    pixel_tick_25 <= tick_reg;
end architecture arch;
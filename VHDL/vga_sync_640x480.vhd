-------------------------------------------------------------------------------
-- Arquivo   : vga_sync_640x480.vhd
-------------------------------------------------------------------------------
-- Descricao : gerador de sincronismo VGA 640x480
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     18/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  versao inicial
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;

entity vga_sync_640x480 is
    port (
        clock      : in std_logic;
        reset      : in std_logic;
        pixel_tick : in std_logic;

        x_pixel : out vga_coord_t;
        y_pixel : out vga_coord_t;

        video_on : out std_logic;

        hsync : out std_logic;
        vsync : out std_logic
    );
end entity vga_sync_640x480;

architecture arch of vga_sync_640x480 is
    signal h_cont : natural range 0 to VGA_H_TOTAL_C-1 := 0;
    signal v_cont : natural range 0 to VGA_V_TOTAL_C-1 := 0;
begin
    process(clock, reset)
    begin
        if reset = '1' then
            h_cont <= 0;
            v_cont <= 0;

        elsif rising_edge(clock) then
            if pixel_tick = '1' then
                if h_cont = VGA_H_TOTAL_C-1 then
                    h_cont <= 0;

                    if v_cont = VGA_V_TOTAL_C-1 then
                        v_cont <= 0;
                    else
                        v_cont <= v_cont + 1;
                    end if;

                else
                    h_cont <= h_cont + 1;
                end if;
            end if;
        end if;
    end process;

    x_pixel <= to_unsigned(h_cont, x_pixel'length) when h_cont < VGA_H_VISIBLE_C
               else (others => '0');

    y_pixel <= to_unsigned(v_cont, y_pixel'length) when v_cont < VGA_V_VISIBLE_C
               else (others => '0');

    video_on <= '1' when h_cont < VGA_H_VISIBLE_C and v_cont < VGA_V_VISIBLE_C else '0';

    hsync <= '0' when
             h_cont >= VGA_H_VISIBLE_C + VGA_H_FP_C and
             h_cont <  VGA_H_VISIBLE_C + VGA_H_FP_C + VGA_H_SYNC_C
             else '1';

    vsync <= '0' when
             v_cont >= VGA_V_VISIBLE_C + VGA_V_FP_C and
             v_cont <  VGA_V_VISIBLE_C + VGA_V_FP_C + VGA_V_SYNC_C
             else '1';
end architecture arch;
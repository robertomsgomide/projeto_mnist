-------------------------------------------------------------------------------
-- Arquivo   : vga_render_mnist.vhd
-------------------------------------------------------------------------------
-- Descricao : renderiza a imagem MNIST na tela VGA
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     18/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  versao inicial
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;

entity vga_render_mnist is
    port (
        x_pixel  : in vga_coord_t;
        y_pixel  : in vga_coord_t;
        video_on : in std_logic;

        imagem : in imagem_mnist_t;

        ativo : out std_logic;
        cor   : out vga_cor_t
    );
end entity vga_render_mnist;

architecture arch of vga_render_mnist is
    signal x_int     : vga_coord_int_t;
    signal y_int     : vga_coord_int_t;
    signal dentro    : std_logic;
    signal pixel_bit : std_logic;
begin
    x_int <= to_integer(x_pixel);
    y_int <= to_integer(y_pixel);

    process(x_int, y_int, video_on, imagem)
        variable dentro_v : std_logic;
        variable col_v    : natural range 0 to IMG_WIDTH_C-1;
        variable lin_v    : natural range 0 to IMG_HEIGHT_C-1;
        variable idx_v    : pixel_index_t;
    begin
        dentro_v := '0';
        col_v    := 0;
        lin_v    := 0;
        idx_v    := 0;

        if video_on = '1' and
           x_int >= VGA_MNIST_X_C and x_int < VGA_MNIST_X_C + VGA_MNIST_W_C and
           y_int >= VGA_MNIST_Y_C and y_int < VGA_MNIST_Y_C + VGA_MNIST_H_C then

            dentro_v := '1';
            col_v    := (x_int - VGA_MNIST_X_C) / VGA_MNIST_SCALE_C;
            lin_v    := (y_int - VGA_MNIST_Y_C) / VGA_MNIST_SCALE_C;
            idx_v    := lin_v * IMG_WIDTH_C + col_v;
        end if;

        dentro <= dentro_v;

        if dentro_v = '1' then
            pixel_bit <= imagem(idx_v);
        else
            pixel_bit <= '0';
        end if;
    end process;

    ativo <= dentro;

    cor <= VGA_PRETO_C  when dentro = '1' and pixel_bit = '1' else
           VGA_BRANCO_C when dentro = '1' and pixel_bit = '0' else
           VGA_PRETO_C;
end architecture arch;

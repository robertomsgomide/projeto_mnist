-------------------------------------------------------------------------------
-- Arquivo   : vga_render_layout.vhd
-------------------------------------------------------------------------------
-- Descricao : renderiza os elementos graficos fixos da interface VGA, incluindo
--             bordas, separadores, area da imagem MNIST, painel de resultados
--             e barra inferior de status.
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     18/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  versao inicial
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;

entity vga_render_layout is
    port (
        x_pixel  : in vga_coord_t;
        y_pixel  : in vga_coord_t;
        video_on : in std_logic;

        mnist_ativo : in std_logic;
        mnist_cor   : in vga_cor_t;

        digitos_ativo : in std_logic;
        digitos_cor   : in vga_cor_t;

        ocupado_sistema : in std_logic;

        rgb_final : out vga_cor_t
    );
end entity vga_render_layout;

architecture arch of vga_render_layout is
    --------------------------------------------------------------------
    -- Cores RGB 4:4:4 locais da interface grafica.
    -- Cores basicas sao reaproveitadas do mnist_tipos_pkg.
    --------------------------------------------------------------------
    constant COR_FUNDO_C       : vga_cor_t := x"112";
    constant COR_FUNDO_BUSY_C  : vga_cor_t := x"221";
    constant COR_PAINEL_C      : vga_cor_t := x"223";
    constant COR_HEADER_C      : vga_cor_t := x"045";
    constant COR_HEADER_BUSY_C : vga_cor_t := x"542";
    constant COR_RODAPE_C      : vga_cor_t := x"182";
    constant COR_LINHA_C       : vga_cor_t := x"68B";
    constant COR_LINHA_SOFT_C  : vga_cor_t := x"345";
    constant COR_IMG_BG_C      : vga_cor_t := x"EEE";

    --------------------------------------------------------------------
    -- Geometria fixa do layout 640x480.
    -- A moldura da imagem deriva das constantes globais da imagem MNIST.
    --------------------------------------------------------------------
    constant X_HEADER_C : natural := 16;
    constant Y_HEADER_C : natural := 12;
    constant W_HEADER_C : natural := 608;
    constant H_HEADER_C : natural := 44;

    constant X_LEFT_C  : natural := 24;
    constant Y_PANEL_C : natural := 66;
    constant W_LEFT_C  : natural := 272;
    constant H_PANEL_C : natural := 348;

    constant X_RIGHT_C : natural := 312;
    constant W_RIGHT_C : natural := 304;

    constant X_FOOTER_C : natural := 16;
    constant Y_FOOTER_C : natural := 426;
    constant W_FOOTER_C : natural := 608;
    constant H_FOOTER_C : natural := 38;

    constant IMG_FRAME_PAD_C : natural := 2;
    constant X_IMG_FRAME_C   : natural := VGA_MNIST_X_C - IMG_FRAME_PAD_C;
    constant Y_IMG_FRAME_C   : natural := VGA_MNIST_Y_C - IMG_FRAME_PAD_C;
    constant W_IMG_FRAME_C   : natural := VGA_MNIST_W_C + 2 * IMG_FRAME_PAD_C;
    constant H_IMG_FRAME_C   : natural := VGA_MNIST_H_C + 2 * IMG_FRAME_PAD_C;

    constant Y_RIGHT_DIV_C : natural := 230;

    signal x_int    : vga_coord_int_t;
    signal y_int    : vga_coord_int_t;
    signal cor_base : vga_cor_t;

    function dentro_rect(
        x  : vga_coord_int_t;
        y  : vga_coord_int_t;
        x0 : natural;
        y0 : natural;
        w  : natural;
        h  : natural
    ) return boolean is
    begin
        return (x >= x0) and (x < x0 + w) and
               (y >= y0) and (y < y0 + h);
    end function;

    function borda_rect(
        x  : vga_coord_int_t;
        y  : vga_coord_int_t;
        x0 : natural;
        y0 : natural;
        w  : natural;
        h  : natural;
        t  : natural
    ) return boolean is
    begin
        if not dentro_rect(x, y, x0, y0, w, h) then
            return false;
        end if;

        return (x < x0 + t) or (x >= x0 + w - t) or
               (y < y0 + t) or (y >= y0 + h - t);
    end function;

    function linha_h(
        x  : vga_coord_int_t;
        y  : vga_coord_int_t;
        x0 : natural;
        x1 : natural;
        y0 : natural;
        t  : natural
    ) return boolean is
    begin
        return (x >= x0) and (x <= x1) and
               (y >= y0) and (y < y0 + t);
    end function;
begin
    x_int <= to_integer(x_pixel);
    y_int <= to_integer(y_pixel);

    cor_base <= COR_FUNDO_BUSY_C when ocupado_sistema = '1' else COR_FUNDO_C;

    process(video_on, x_int, y_int,
            mnist_ativo, mnist_cor, digitos_ativo, digitos_cor,
            ocupado_sistema, cor_base)
        variable cor_layout : vga_cor_t;
    begin
        cor_layout := cor_base;

        if video_on = '0' then
            rgb_final <= VGA_PRETO_C;

        else
            if dentro_rect(x_int, y_int, X_HEADER_C, Y_HEADER_C, W_HEADER_C, H_HEADER_C) then
                if ocupado_sistema = '1' then
                    cor_layout := COR_HEADER_BUSY_C;
                else
                    cor_layout := COR_HEADER_C;
                end if;

            elsif dentro_rect(x_int, y_int, X_LEFT_C, Y_PANEL_C, W_LEFT_C, H_PANEL_C) then
                cor_layout := COR_PAINEL_C;

            elsif dentro_rect(x_int, y_int, X_RIGHT_C, Y_PANEL_C, W_RIGHT_C, H_PANEL_C) then
                cor_layout := COR_PAINEL_C;

            elsif dentro_rect(x_int, y_int, X_FOOTER_C, Y_FOOTER_C, W_FOOTER_C, H_FOOTER_C) then
                cor_layout := COR_RODAPE_C;
            end if;

            if dentro_rect(x_int, y_int, X_IMG_FRAME_C, Y_IMG_FRAME_C, W_IMG_FRAME_C, H_IMG_FRAME_C) then
                cor_layout := COR_IMG_BG_C;
            end if;

            if borda_rect(x_int, y_int, X_HEADER_C,    Y_HEADER_C,    W_HEADER_C,    H_HEADER_C,    2) or
               borda_rect(x_int, y_int, X_LEFT_C,      Y_PANEL_C,     W_LEFT_C,      H_PANEL_C,     2) or
               borda_rect(x_int, y_int, X_RIGHT_C,     Y_PANEL_C,     W_RIGHT_C,     H_PANEL_C,     2) or
               borda_rect(x_int, y_int, X_FOOTER_C,    Y_FOOTER_C,    W_FOOTER_C,    H_FOOTER_C,    2) or
               borda_rect(x_int, y_int, X_IMG_FRAME_C, Y_IMG_FRAME_C, W_IMG_FRAME_C, H_IMG_FRAME_C, 2) then
                cor_layout := COR_LINHA_C;

            elsif linha_h(x_int, y_int, X_RIGHT_C + 8, X_RIGHT_C + W_RIGHT_C - 8, Y_RIGHT_DIV_C, 2) then
                cor_layout := COR_LINHA_SOFT_C;
            end if;

            if digitos_ativo = '1' then
                rgb_final <= digitos_cor;
            elsif mnist_ativo = '1' then
                rgb_final <= mnist_cor;
            else
                rgb_final <= cor_layout;
            end if;
        end if;
    end process;
end architecture arch;
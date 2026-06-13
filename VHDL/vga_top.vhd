-------------------------------------------------------------------------------
-- Arquivo   : vga_top.vhd
-------------------------------------------------------------------------------
-- Descricao : topo da interface VGA. Integra temporizacao 640x480, renderizacao
--             da imagem MNIST ampliada, camada textual e layout grafico da tela.
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     18/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  versao inicial
--     19/05/2026  1.1     Roberto M S Gomide / Rodrigo Haruna  integracao das camadas VGA
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;

entity vga_top is
    port (
        clock_50 : in std_logic;
        reset    : in std_logic;

        imagem : in imagem_mnist_t;

        escrita_habilitada : in std_logic;
        imagem_valida      : in std_logic;

        uart_recebendo    : in std_logic;
        pacote_ok_pulso   : in std_logic;
        pacote_erro_pulso : in std_logic;
        erro_codigo       : in uart_erro_t;

        classificacao_ocupada : in std_logic;
        resultado_valido      : in std_logic;
        classificadores_concordam : in std_logic;

        digito_binario : in digito_t;
        digito_denso   : in digito_t;

        estado_uc : in estado_uc_t;

        vga_r  : out std_logic_vector(3 downto 0);
        vga_g  : out std_logic_vector(3 downto 0);
        vga_b  : out std_logic_vector(3 downto 0);
        vga_hs : out std_logic;
        vga_vs : out std_logic
    );
end entity vga_top;

architecture estrutural of vga_top is

    component divisor_clock_25mhz is
        port (
            clock_50 : in std_logic;
            reset    : in std_logic;

            pixel_tick_25 : out std_logic
        );
    end component;

    component vga_sync_640x480 is
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
    end component;

    component vga_render_mnist is
        port (
            x_pixel  : in vga_coord_t;
            y_pixel  : in vga_coord_t;
            video_on : in std_logic;

            imagem : in imagem_mnist_t;

            ativo : out std_logic;
            cor   : out vga_cor_t
        );
    end component;

    component vga_render_fonts is
        port (
            clock      : in std_logic;
            reset      : in std_logic;
            pixel_tick : in std_logic;

            x_pixel  : in vga_coord_t;
            y_pixel  : in vga_coord_t;
            video_on : in std_logic;

            escrita_habilitada : in std_logic;
            imagem_valida      : in std_logic;

            uart_recebendo    : in std_logic;
            pacote_ok_pulso   : in std_logic;
            pacote_erro_pulso : in std_logic;
            erro_codigo       : in uart_erro_t;

            classificacao_ocupada : in std_logic;
            resultado_valido      : in std_logic;
            classificadores_concordam : in std_logic;

            digito_binario : in digito_t;
            digito_denso   : in digito_t;

            estado_uc : in estado_uc_t;

            ativo : out std_logic;
            cor   : out vga_cor_t
        );
    end component;

    component vga_render_layout is
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
    end component;

    signal pixel_tick_25_s : std_logic := '0';
    signal x_pixel_s       : vga_coord_t := (others => '0');
    signal y_pixel_s       : vga_coord_t := (others => '0');
    signal video_on_s      : std_logic := '0';

    signal mnist_ativo_s : std_logic := '0';
    signal fonts_ativo_s : std_logic := '0';

    signal mnist_cor_s : vga_cor_t := VGA_PRETO_C;
    signal fonts_cor_s : vga_cor_t := VGA_PRETO_C;
    signal rgb_final_s : vga_cor_t := VGA_PRETO_C;

begin

    u_divisor_clock : divisor_clock_25mhz
        port map (
            clock_50      => clock_50,
            reset         => reset,
            pixel_tick_25 => pixel_tick_25_s
        );

    u_vga_sync : vga_sync_640x480
        port map (
            clock      => clock_50,
            reset      => reset,
            pixel_tick => pixel_tick_25_s,
            x_pixel    => x_pixel_s,
            y_pixel    => y_pixel_s,
            video_on   => video_on_s,
            hsync      => vga_hs,
            vsync      => vga_vs
        );

    u_render_mnist : vga_render_mnist
        port map (
            x_pixel  => x_pixel_s,
            y_pixel  => y_pixel_s,
            video_on => video_on_s,
            imagem   => imagem,
            ativo    => mnist_ativo_s,
            cor      => mnist_cor_s
        );

    u_render_fonts : vga_render_fonts
        port map (
            clock                    => clock_50,
            reset                    => reset,
            pixel_tick               => pixel_tick_25_s,
            x_pixel                  => x_pixel_s,
            y_pixel                  => y_pixel_s,
            video_on                 => video_on_s,
            escrita_habilitada       => escrita_habilitada,
            imagem_valida            => imagem_valida,
            uart_recebendo           => uart_recebendo,
            pacote_ok_pulso          => pacote_ok_pulso,
            pacote_erro_pulso        => pacote_erro_pulso,
            erro_codigo              => erro_codigo,
            classificacao_ocupada    => classificacao_ocupada,
            resultado_valido         => resultado_valido,
            classificadores_concordam => classificadores_concordam,
            digito_binario           => digito_binario,
            digito_denso             => digito_denso,
            estado_uc                => estado_uc,
            ativo                    => fonts_ativo_s,
            cor                      => fonts_cor_s
        );

    u_render_layout : vga_render_layout
        port map (
            x_pixel          => x_pixel_s,
            y_pixel          => y_pixel_s,
            video_on         => video_on_s,
            mnist_ativo      => mnist_ativo_s,
            mnist_cor        => mnist_cor_s,
            digitos_ativo    => fonts_ativo_s,
            digitos_cor      => fonts_cor_s,
            ocupado_sistema  => classificacao_ocupada,
            rgb_final        => rgb_final_s
        );

    vga_r <= rgb_final_s(11 downto 8);
    vga_g <= rgb_final_s(7 downto 4);
    vga_b <= rgb_final_s(3 downto 0);

end architecture estrutural;

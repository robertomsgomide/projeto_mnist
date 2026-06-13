-------------------------------------------------------------------------------
-- Arquivo   : vga_render_fonts.vhd
-------------------------------------------------------------------------------
-- Descricao : renderiza os textos da interface VGA do projeto com entrada
--             dinamica. Exibe status UART, validade da imagem, predicoes,
--             latencia deterministica e concordancia entre classificadores.
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     18/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  versao inicial
--     19/05/2026  1.1     Roberto M S Gomide / Rodrigo Haruna  GUI do canvas dinamico
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;
use work.font_5x7_pkg.all;

entity vga_render_fonts is
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
end entity vga_render_fonts;

architecture arch of vga_render_fonts is

    --------------------------------------------------------------------
    -- Cores RGB 4:4:4 da camada textual.
    --------------------------------------------------------------------
    constant COR_TITULO_C : vga_cor_t := x"BDF";
    constant COR_LABEL_C  : vga_cor_t := x"DDE";
    constant COR_VALOR_C  : vga_cor_t := x"FFF";
    constant COR_INFO_C   : vga_cor_t := x"FD7";
    constant COR_OK_C     : vga_cor_t := x"3F8";
    constant COR_ALERTA_C : vga_cor_t := x"F55";

    --------------------------------------------------------------------
    -- Escalas da fonte 5x7 e celulas de texto.
    --------------------------------------------------------------------
    constant ESC_TITULO_C : natural := 2;
    constant ESC_TEXTO_C  : natural := 2;
    constant ESC_RODAPE_C : natural := 1;

    constant CELL_W_E2_C : natural := (FONT_W_C + 1) * ESC_TEXTO_C;
    constant CELL_H_E2_C : natural := FONT_H_C * ESC_TEXTO_C;
    constant CELL_W_E1_C : natural := (FONT_W_C + 1) * ESC_RODAPE_C;
    constant CELL_H_E1_C : natural := FONT_H_C * ESC_RODAPE_C;

    --------------------------------------------------------------------
    -- Geometria textual, alinhada ao layout 640x480.
    --------------------------------------------------------------------
    constant X_TITULO_C : natural := 158;
    constant Y_TITULO_C : natural := 28;

    constant X_CANVAS_TIT_C : natural := 124;
    constant Y_CANVAS_TIT_C : natural := 96;
    constant X_CANVAS_DIM_C : natural := 86;
    constant Y_CANVAS_DIM_C : natural := 384;

    constant X_RIGHT_C      : natural := 330;
    constant Y_BIN_TIT_C    : natural := 92;
    constant Y_BIN_PRED_C   : natural := 124;
    constant Y_BIN_ACC_C    : natural := 154;
    constant Y_BIN_LAT_C    : natural := 184;

    constant Y_DEN_TIT_C    : natural := 248;
    constant Y_DEN_PRED_C   : natural := 280;
    constant Y_DEN_ACC_C    : natural := 310;
    constant Y_DEN_LAT_C    : natural := 340;

    constant X_PRED_VAL_C     : natural := X_RIGHT_C + 10 * CELL_W_E2_C;
    constant X_LAT_D0_C       : natural := X_RIGHT_C + 10 * CELL_W_E2_C;
    constant X_LAT_D1_C       : natural := X_LAT_D0_C + CELL_W_E2_C;
    constant X_LAT_D2_C       : natural := X_LAT_D1_C + CELL_W_E2_C;
    constant X_LAT_D3_C       : natural := X_LAT_D2_C + CELL_W_E2_C;
    constant X_LAT_SUFFIX_C   : natural := X_LAT_D3_C + CELL_W_E2_C;

    constant X_FOOT_UART_L_C  : natural := 28;
    constant X_FOOT_UART_V_C  : natural := 64;
    constant X_FOOT_IMG_L_C   : natural := 112;
    constant X_FOOT_IMG_V_C   : natural := 172;
    constant X_FOOT_ST_L_C    : natural := 222;
    constant X_FOOT_ST_V_C    : natural := 288;
    constant X_FOOT_MATCH_L_C : natural := 382;
    constant X_FOOT_MATCH_V_C : natural := 442;
    constant Y_FOOT_C         : natural := 440;

    --------------------------------------------------------------------
    -- Larguras em caracteres.
    --------------------------------------------------------------------
    constant CH_TITULO_C      : natural := 27;
    constant CH_CANVAS_TIT_C  : natural := 6;
    constant CH_CANVAS_DIM_C  : natural := 17;
    constant CH_BIN_TIT_C     : natural := 21;
    constant CH_DEN_TIT_C     : natural := 19;
    constant CH_PRED_L_C      : natural := 10;
    constant CH_PRED_V_C      : natural := 1;
    constant CH_ACC_C         : natural := 22;
    constant CH_BIN_LAT_C     : natural := 23;
    constant CH_DEN_LAT_L_C   : natural := 24;

    constant CH_FOOT_UART_L_C  : natural := 6;
    constant CH_FOOT_UART_V_C  : natural := 6;
    constant CH_FOOT_IMG_L_C   : natural := 10;
    constant CH_FOOT_IMG_V_C   : natural := 7;
    constant CH_FOOT_ST_L_C    : natural := 11;
    constant CH_FOOT_ST_V_C    : natural := 13;
    constant CH_FOOT_MATCH_L_C : natural := 10;
    constant CH_FOOT_MATCH_V_C : natural := 3;

    constant W_TITULO_C      : natural := CH_TITULO_C * CELL_W_E2_C;
    constant W_CANVAS_TIT_C  : natural := CH_CANVAS_TIT_C * CELL_W_E2_C;
    constant W_CANVAS_DIM_C  : natural := CH_CANVAS_DIM_C * CELL_W_E2_C;
    constant W_BIN_TIT_C     : natural := CH_BIN_TIT_C * CELL_W_E2_C;
    constant W_DEN_TIT_C     : natural := CH_DEN_TIT_C * CELL_W_E2_C;
    constant W_PRED_L_C      : natural := CH_PRED_L_C * CELL_W_E2_C;
    constant W_PRED_V_C      : natural := CH_PRED_V_C * CELL_W_E2_C;
    constant W_ACC_C         : natural := CH_ACC_C * CELL_W_E2_C;
    constant W_BIN_LAT_C     : natural := CH_BIN_LAT_C * CELL_W_E2_C;
    constant W_DEN_LAT_L_C   : natural := CH_DEN_LAT_L_C * CELL_W_E2_C;
    constant W_FOOT_UART_L_C  : natural := CH_FOOT_UART_L_C * CELL_W_E1_C;
    constant W_FOOT_UART_V_C  : natural := CH_FOOT_UART_V_C * CELL_W_E1_C;
    constant W_FOOT_IMG_L_C   : natural := CH_FOOT_IMG_L_C * CELL_W_E1_C;
    constant W_FOOT_IMG_V_C   : natural := CH_FOOT_IMG_V_C * CELL_W_E1_C;
    constant W_FOOT_ST_L_C    : natural := CH_FOOT_ST_L_C * CELL_W_E1_C;
    constant W_FOOT_ST_V_C    : natural := CH_FOOT_ST_V_C * CELL_W_E1_C;
    constant W_FOOT_MATCH_L_C : natural := CH_FOOT_MATCH_L_C * CELL_W_E1_C;
    constant W_FOOT_MATCH_V_C : natural := CH_FOOT_MATCH_V_C * CELL_W_E1_C;

    --------------------------------------------------------------------
    -- Estado de varredura por regiao de texto. Os contadores evitam
    -- calcular divisoes/modulos para cada string a cada pixel.
    --------------------------------------------------------------------
    constant CELL_COL_MAX_C : natural := CELL_W_E2_C - 1;
    constant CELL_ROW_MAX_C : natural := CELL_H_E2_C - 1;
    constant CHAR_IDX_MAX_C : natural := 31;

    constant UART_OK_HOLD_FRAMES_C : natural := 60;

    type reg_t is record
        active   : std_logic;
        cell_col : natural range 0 to CELL_COL_MAX_C;
        cell_row : natural range 0 to CELL_ROW_MAX_C;
        char_idx : natural range 0 to CHAR_IDX_MAX_C;
    end record;

    constant REG_INIT_C : reg_t := (
        active   => '0',
        cell_col => 0,
        cell_row => 0,
        char_idx => 0
    );

    signal r_titulo      : reg_t := REG_INIT_C;
    signal r_canvas_tit  : reg_t := REG_INIT_C;
    signal r_canvas_dim  : reg_t := REG_INIT_C;

    signal r_bin_tit      : reg_t := REG_INIT_C;
    signal r_bin_pred_l   : reg_t := REG_INIT_C;
    signal r_bin_pred_v   : reg_t := REG_INIT_C;
    signal r_bin_acc      : reg_t := REG_INIT_C;
    signal r_bin_lat      : reg_t := REG_INIT_C;

    signal r_den_tit      : reg_t := REG_INIT_C;
    signal r_den_pred_l   : reg_t := REG_INIT_C;
    signal r_den_pred_v   : reg_t := REG_INIT_C;
    signal r_den_acc      : reg_t := REG_INIT_C;
    signal r_den_lat_l    : reg_t := REG_INIT_C;

    signal r_foot_uart_l  : reg_t := REG_INIT_C;
    signal r_foot_uart_v  : reg_t := REG_INIT_C;
    signal r_foot_img_l   : reg_t := REG_INIT_C;
    signal r_foot_img_v   : reg_t := REG_INIT_C;
    signal r_foot_st_l    : reg_t := REG_INIT_C;
    signal r_foot_st_v    : reg_t := REG_INIT_C;
    signal r_foot_match_l : reg_t := REG_INIT_C;
    signal r_foot_match_v : reg_t := REG_INIT_C;

    signal uart_ok_hold_frames_s : natural range 0 to UART_OK_HOLD_FRAMES_C := 0;

    function next_reg_state(
        s_curr : reg_t;
        xi     : natural;
        yi     : natural;
        x0     : natural;
        y0     : natural;
        cell_w : natural;
        cell_h : natural;
        width  : natural
    ) return reg_t is
        variable s_next : reg_t;
    begin
        s_next := s_curr;

        if yi >= y0 and yi < y0 + cell_h and
           xi + 1 >= x0 and xi + 1 < x0 + width then
            s_next.active   := '1';
            s_next.cell_row := yi - y0;

            if xi + 1 = x0 then
                s_next.cell_col := 0;
                s_next.char_idx := 0;
            elsif s_curr.cell_col = cell_w - 1 then
                s_next.cell_col := 0;
                s_next.char_idx := s_curr.char_idx + 1;
            else
                s_next.cell_col := s_curr.cell_col + 1;
            end if;
        else
            s_next.active := '0';
        end if;

        return s_next;
    end function;

    function lit_text(
        s      : reg_t;
        texto  : string;
        escala : natural
    ) return std_logic is
        variable col_in_font : natural;
        variable row_in_font : natural;
        variable c           : character;
    begin
        if s.active = '0' then
            return '0';
        end if;

        if s.char_idx >= texto'length then
            return '0';
        end if;

        col_in_font := s.cell_col / escala;
        row_in_font := s.cell_row / escala;

        if col_in_font >= FONT_W_C then
            return '0';
        end if;

        c := texto(texto'low + s.char_idx);
        return pixel_char(c, integer(col_in_font), integer(row_in_font));
    end function;

    function lit_digit(
        s      : reg_t;
        d      : natural;
        escala : natural
    ) return std_logic is
        variable col_in_font : natural;
        variable row_in_font : natural;
    begin
        if s.active = '0' or s.char_idx /= 0 then
            return '0';
        end if;

        col_in_font := s.cell_col / escala;
        row_in_font := s.cell_row / escala;

        if col_in_font >= FONT_W_C then
            return '0';
        end if;

        return pixel_font(integer(d), integer(col_in_font), integer(row_in_font));
    end function;

begin

    proc_state: process(clock, reset)
        variable xi : natural;
        variable yi : natural;
    begin
        if reset = '1' then
            r_titulo     <= REG_INIT_C;
            r_canvas_tit <= REG_INIT_C;
            r_canvas_dim <= REG_INIT_C;

            r_bin_tit    <= REG_INIT_C;
            r_bin_pred_l <= REG_INIT_C;
            r_bin_pred_v <= REG_INIT_C;
            r_bin_acc    <= REG_INIT_C;
            r_bin_lat    <= REG_INIT_C;

            r_den_tit     <= REG_INIT_C;
            r_den_pred_l  <= REG_INIT_C;
            r_den_pred_v  <= REG_INIT_C;
            r_den_acc     <= REG_INIT_C;
            r_den_lat_l   <= REG_INIT_C;

            r_foot_uart_l  <= REG_INIT_C;
            r_foot_uart_v  <= REG_INIT_C;
            r_foot_img_l   <= REG_INIT_C;
            r_foot_img_v   <= REG_INIT_C;
            r_foot_st_l    <= REG_INIT_C;
            r_foot_st_v    <= REG_INIT_C;
            r_foot_match_l <= REG_INIT_C;
            r_foot_match_v <= REG_INIT_C;

            uart_ok_hold_frames_s <= 0;

        elsif rising_edge(clock) then
            if pacote_ok_pulso = '1' then
                uart_ok_hold_frames_s <= UART_OK_HOLD_FRAMES_C;

            elsif pixel_tick = '1' and video_on = '1' and
                  x_pixel = to_unsigned(0, x_pixel'length) and
                  y_pixel = to_unsigned(0, y_pixel'length) and
                  uart_ok_hold_frames_s > 0 then
                uart_ok_hold_frames_s <= uart_ok_hold_frames_s - 1;
            end if;

            if pixel_tick = '1' then
                xi := to_integer(x_pixel);
                yi := to_integer(y_pixel);

                r_titulo     <= next_reg_state(r_titulo,     xi, yi, X_TITULO_C,     Y_TITULO_C,     CELL_W_E2_C, CELL_H_E2_C, W_TITULO_C);
                r_canvas_tit <= next_reg_state(r_canvas_tit, xi, yi, X_CANVAS_TIT_C, Y_CANVAS_TIT_C, CELL_W_E2_C, CELL_H_E2_C, W_CANVAS_TIT_C);
                r_canvas_dim <= next_reg_state(r_canvas_dim, xi, yi, X_CANVAS_DIM_C, Y_CANVAS_DIM_C, CELL_W_E2_C, CELL_H_E2_C, W_CANVAS_DIM_C);

                r_bin_tit    <= next_reg_state(r_bin_tit,    xi, yi, X_RIGHT_C,      Y_BIN_TIT_C,    CELL_W_E2_C, CELL_H_E2_C, W_BIN_TIT_C);
                r_bin_pred_l <= next_reg_state(r_bin_pred_l, xi, yi, X_RIGHT_C,      Y_BIN_PRED_C,   CELL_W_E2_C, CELL_H_E2_C, W_PRED_L_C);
                r_bin_pred_v <= next_reg_state(r_bin_pred_v, xi, yi, X_PRED_VAL_C,   Y_BIN_PRED_C,   CELL_W_E2_C, CELL_H_E2_C, W_PRED_V_C);
                r_bin_acc    <= next_reg_state(r_bin_acc,    xi, yi, X_RIGHT_C,      Y_BIN_ACC_C,    CELL_W_E2_C, CELL_H_E2_C, W_ACC_C);
                r_bin_lat    <= next_reg_state(r_bin_lat,    xi, yi, X_RIGHT_C,      Y_BIN_LAT_C,    CELL_W_E2_C, CELL_H_E2_C, W_BIN_LAT_C);

                r_den_tit     <= next_reg_state(r_den_tit,     xi, yi, X_RIGHT_C,      Y_DEN_TIT_C,  CELL_W_E2_C, CELL_H_E2_C, W_DEN_TIT_C);
                r_den_pred_l  <= next_reg_state(r_den_pred_l,  xi, yi, X_RIGHT_C,      Y_DEN_PRED_C, CELL_W_E2_C, CELL_H_E2_C, W_PRED_L_C);
                r_den_pred_v  <= next_reg_state(r_den_pred_v,  xi, yi, X_PRED_VAL_C,   Y_DEN_PRED_C, CELL_W_E2_C, CELL_H_E2_C, W_PRED_V_C);
                r_den_acc     <= next_reg_state(r_den_acc,     xi, yi, X_RIGHT_C,      Y_DEN_ACC_C,  CELL_W_E2_C, CELL_H_E2_C, W_ACC_C);
                r_den_lat_l   <= next_reg_state(r_den_lat_l,   xi, yi, X_RIGHT_C,      Y_DEN_LAT_C,  CELL_W_E2_C, CELL_H_E2_C, W_DEN_LAT_L_C);

                r_foot_uart_l  <= next_reg_state(r_foot_uart_l,  xi, yi, X_FOOT_UART_L_C,  Y_FOOT_C, CELL_W_E1_C, CELL_H_E1_C, W_FOOT_UART_L_C);
                r_foot_uart_v  <= next_reg_state(r_foot_uart_v,  xi, yi, X_FOOT_UART_V_C,  Y_FOOT_C, CELL_W_E1_C, CELL_H_E1_C, W_FOOT_UART_V_C);
                r_foot_img_l   <= next_reg_state(r_foot_img_l,   xi, yi, X_FOOT_IMG_L_C,   Y_FOOT_C, CELL_W_E1_C, CELL_H_E1_C, W_FOOT_IMG_L_C);
                r_foot_img_v   <= next_reg_state(r_foot_img_v,   xi, yi, X_FOOT_IMG_V_C,   Y_FOOT_C, CELL_W_E1_C, CELL_H_E1_C, W_FOOT_IMG_V_C);
                r_foot_st_l    <= next_reg_state(r_foot_st_l,    xi, yi, X_FOOT_ST_L_C,    Y_FOOT_C, CELL_W_E1_C, CELL_H_E1_C, W_FOOT_ST_L_C);
                r_foot_st_v    <= next_reg_state(r_foot_st_v,    xi, yi, X_FOOT_ST_V_C,    Y_FOOT_C, CELL_W_E1_C, CELL_H_E1_C, W_FOOT_ST_V_C);
                r_foot_match_l <= next_reg_state(r_foot_match_l, xi, yi, X_FOOT_MATCH_L_C, Y_FOOT_C, CELL_W_E1_C, CELL_H_E1_C, W_FOOT_MATCH_L_C);
                r_foot_match_v <= next_reg_state(r_foot_match_v, xi, yi, X_FOOT_MATCH_V_C, Y_FOOT_C, CELL_W_E1_C, CELL_H_E1_C, W_FOOT_MATCH_V_C);
            end if;
        end if;
    end process proc_state;

    proc_out: process(
        video_on,
        r_titulo, r_canvas_tit, r_canvas_dim,
        r_bin_tit, r_bin_pred_l, r_bin_pred_v, r_bin_acc, r_bin_lat,
        r_den_tit, r_den_pred_l, r_den_pred_v, r_den_acc,
        r_den_lat_l,
        r_foot_uart_l, r_foot_uart_v, r_foot_img_l, r_foot_img_v,
        r_foot_st_l, r_foot_st_v, r_foot_match_l, r_foot_match_v,
        escrita_habilitada, imagem_valida,
        uart_recebendo, pacote_erro_pulso, erro_codigo, uart_ok_hold_frames_s,
        classificacao_ocupada, resultado_valido,
        classificadores_concordam, digito_binario, digito_denso,
        estado_uc
    )
        variable aceso     : std_logic;
        variable cor_local : vga_cor_t;
    begin
        aceso     := '0';
        cor_local := COR_LABEL_C;

        if video_on = '1' then
            if lit_text(r_titulo, "CLASSIFICADOR MNIST EM FPGA", ESC_TITULO_C) = '1' then
                aceso     := '1';
                cor_local := COR_TITULO_C;

            elsif lit_text(r_canvas_tit, "CANVAS", ESC_TEXTO_C) = '1' then
                aceso     := '1';
                cor_local := COR_TITULO_C;

            elsif lit_text(r_canvas_dim, "28X28 -> 224X224", ESC_TEXTO_C) = '1' then
                aceso     := '1';
                cor_local := COR_INFO_C;

            elsif lit_text(r_bin_tit, "CLASSIFICADOR BINARIO", ESC_TEXTO_C) = '1' then
                aceso     := '1';
                cor_local := COR_TITULO_C;

            elsif lit_text(r_bin_pred_l, "PREDICAO: ", ESC_TEXTO_C) = '1' then
                aceso     := '1';
                cor_local := COR_LABEL_C;

            elsif resultado_valido = '1' and
                  lit_digit(r_bin_pred_v, to_integer(digito_binario), ESC_TEXTO_C) = '1' then
                aceso     := '1';
                cor_local := COR_OK_C;

            elsif resultado_valido = '0' and
                  lit_text(r_bin_pred_v, "?", ESC_TEXTO_C) = '1' then
                aceso     := '1';
                cor_local := COR_INFO_C;

            elsif lit_text(r_bin_acc, "ACURACIA REF.: ~71%", ESC_TEXTO_C) = '1' then
                aceso     := '1';
                cor_local := COR_INFO_C;

            elsif lit_text(r_bin_lat, "LATENCIA: COMB./1 CICLO", ESC_TEXTO_C) = '1' then
                aceso     := '1';
                cor_local := COR_INFO_C;

            elsif lit_text(r_den_tit, "CLASSIFICADOR DENSO", ESC_TEXTO_C) = '1' then
                aceso     := '1';
                cor_local := COR_TITULO_C;

            elsif lit_text(r_den_pred_l, "PREDICAO: ", ESC_TEXTO_C) = '1' then
                aceso     := '1';
                cor_local := COR_LABEL_C;

            elsif resultado_valido = '1' and
                  lit_digit(r_den_pred_v, to_integer(digito_denso), ESC_TEXTO_C) = '1' then
                aceso     := '1';
                cor_local := COR_OK_C;

            elsif resultado_valido = '0' and
                  lit_text(r_den_pred_v, "?", ESC_TEXTO_C) = '1' then
                aceso     := '1';
                cor_local := COR_INFO_C;

            elsif lit_text(r_den_acc, "ACURACIA REF.: ~92%", ESC_TEXTO_C) = '1' then
                aceso     := '1';
                cor_local := COR_INFO_C;

            elsif lit_text(r_den_lat_l, "LATENCIA: 796 CICLOS", ESC_TEXTO_C) = '1' then
                aceso     := '1';
                cor_local := COR_INFO_C;

            elsif lit_text(r_foot_uart_l, "UART: ", ESC_RODAPE_C) = '1' then
                aceso     := '1';
                cor_local := COR_LABEL_C;

            elsif (erro_codigo /= UART_ERRO_NENHUM_C or pacote_erro_pulso = '1') and
                  lit_text(r_foot_uart_v, "ERRO", ESC_RODAPE_C) = '1' then
                aceso     := '1';
                cor_local := COR_ALERTA_C;

            elsif erro_codigo = UART_ERRO_NENHUM_C and pacote_erro_pulso = '0' and
                  uart_recebendo = '1' and
                  lit_text(r_foot_uart_v, "RX", ESC_RODAPE_C) = '1' then
                aceso     := '1';
                cor_local := COR_INFO_C;

            elsif erro_codigo = UART_ERRO_NENHUM_C and pacote_erro_pulso = '0' and
                  uart_recebendo = '0' and uart_ok_hold_frames_s > 0 and
                  lit_text(r_foot_uart_v, "OK", ESC_RODAPE_C) = '1' then
                aceso     := '1';
                cor_local := COR_OK_C;

            elsif erro_codigo = UART_ERRO_NENHUM_C and pacote_erro_pulso = '0' and
                  uart_recebendo = '0' and uart_ok_hold_frames_s = 0 and
                  lit_text(r_foot_uart_v, "PRONTO", ESC_RODAPE_C) = '1' then
                aceso     := '1';
                cor_local := COR_OK_C;

            elsif lit_text(r_foot_img_l, " | IMAGEM: ", ESC_RODAPE_C) = '1' then
                aceso     := '1';
                cor_local := COR_LABEL_C;

            elsif imagem_valida = '1' and
                  lit_text(r_foot_img_v, "VALIDA", ESC_RODAPE_C) = '1' then
                aceso     := '1';
                cor_local := COR_OK_C;

            elsif imagem_valida = '0' and
                  lit_text(r_foot_img_v, "VAZIA", ESC_RODAPE_C) = '1' then
                aceso     := '1';
                cor_local := COR_INFO_C;

            elsif lit_text(r_foot_st_l, " | STATUS: ", ESC_RODAPE_C) = '1' then
                aceso     := '1';
                cor_local := COR_LABEL_C;

            elsif escrita_habilitada = '1' and
                  lit_text(r_foot_st_v, "DESENHANDO", ESC_RODAPE_C) = '1' then
                aceso     := '1';
                cor_local := COR_INFO_C;

            elsif escrita_habilitada = '0' and classificacao_ocupada = '1' and
                  lit_text(r_foot_st_v, "CLASSIFICANDO", ESC_RODAPE_C) = '1' then
                aceso     := '1';
                cor_local := COR_INFO_C;

            elsif escrita_habilitada = '0' and classificacao_ocupada = '0' and resultado_valido = '1' and
                  lit_text(r_foot_st_v, "CLASSIFICADO", ESC_RODAPE_C) = '1' then
                aceso     := '1';
                cor_local := COR_OK_C;

            elsif escrita_habilitada = '0' and classificacao_ocupada = '0' and resultado_valido = '0' and
                  estado_uc = UC_IDLE_C and imagem_valida = '1' and
                  lit_text(r_foot_st_v, "SALVO", ESC_RODAPE_C) = '1' then
                aceso     := '1';
                cor_local := COR_INFO_C;

            elsif escrita_habilitada = '0' and classificacao_ocupada = '0' and resultado_valido = '0' and
                  not (estado_uc = UC_IDLE_C and imagem_valida = '1') and
                  lit_text(r_foot_st_v, "AGUARDA", ESC_RODAPE_C) = '1' then
                aceso     := '1';
                cor_local := COR_INFO_C;

            elsif lit_text(r_foot_match_l, " | MATCH: ", ESC_RODAPE_C) = '1' then
                aceso     := '1';
                cor_local := COR_LABEL_C;

            elsif resultado_valido = '1' and classificadores_concordam = '1' and
                  lit_text(r_foot_match_v, "SIM", ESC_RODAPE_C) = '1' then
                aceso     := '1';
                cor_local := COR_OK_C;

            elsif resultado_valido = '1' and classificadores_concordam = '0' and
                  lit_text(r_foot_match_v, "NAO", ESC_RODAPE_C) = '1' then
                aceso     := '1';
                cor_local := COR_ALERTA_C;

            elsif resultado_valido = '0' and
                  lit_text(r_foot_match_v, "?", ESC_RODAPE_C) = '1' then
                aceso     := '1';
                cor_local := COR_INFO_C;
            end if;
        end if;

        ativo <= aceso;
        cor   <= cor_local;
    end process proc_out;

end architecture arch;

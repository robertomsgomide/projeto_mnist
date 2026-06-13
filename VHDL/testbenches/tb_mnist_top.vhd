-------------------------------------------------------------------------------
-- Arquivo gerado automaticamente por python/monta_tb.py
-- Sessao : python/sim_logs/session_20260612_135332/session.json
-- Gerado : 2026-06-12T22:33:43
--
-- Replay por UART e controles logicos sincronizados.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use std.textio.all;
use work.mnist_tipos_pkg.all;
use work.tb_uart_mnist_pkg.all;

entity tb_mnist_top is
end entity tb_mnist_top;

architecture sim of tb_mnist_top is

    constant TB_CONTROL_SYNC_WAIT_C : natural := 4;
    constant TB_RESULT_TIMEOUT_C : natural := 10000;
    constant TB_POST_PACKET_WAIT_C : natural := 20;
    constant TB_REPORT_CANVAS_DIFFS_C : boolean := true;
    constant TB_VERBOSE_C : boolean := false;

    signal clock_50 : std_logic := '0';

    signal escreve    : std_logic := '0';
    signal apaga      : std_logic := '0';
    signal classifica : std_logic := '0';

    signal uart_rx_serial : std_logic := '1';
    signal uart_tx_serial : std_logic;

    signal ledr : led_bus_t;
    signal hex0 : hex7seg_t;
    signal hex1 : hex7seg_t;
    signal hex2 : hex7seg_t;
    signal hex3 : hex7seg_t;
    signal hex4 : hex7seg_t;
    signal hex5 : hex7seg_t;

    signal vga_r  : std_logic_vector(3 downto 0);
    signal vga_g  : std_logic_vector(3 downto 0);
    signal vga_b  : std_logic_vector(3 downto 0);
    signal vga_hs : std_logic;
    signal vga_vs : std_logic;

    signal reset_sistema_s      : std_logic := '0';
    signal escrita_habilitada_s : std_logic := '0';
    signal limpa_canvas_pulso_s : std_logic := '0';
    signal classifica_pulso_s   : std_logic := '0';

    signal frame_recebido_s        : imagem_mnist_t := (others => '0');
    signal frame_recebido_valido_s : std_logic := '0';

    signal uart_recebendo_s    : std_logic := '0';
    signal pacote_ok_pulso_s   : std_logic := '0';
    signal pacote_erro_pulso_s : std_logic := '0';
    signal erro_codigo_s       : uart_erro_t := UART_ERRO_NENHUM_C;
    signal seq_ultimo_s        : uart_seq_t := (others => '0');

    signal imagem_canvas_s         : imagem_mnist_t := (others => '0');
    signal imagem_valida_s         : std_logic := '0';
    signal imagem_alterada_pulso_s : std_logic := '0';

    signal inicia_denso_s       : std_logic := '0';
    signal registra_resultado_s : std_logic := '0';
    signal limpa_resultado_s    : std_logic := '0';
    signal denso_pronto_s       : std_logic := '0';

    signal classificacao_ocupada_s : std_logic := '0';
    signal resultado_pendente_s    : std_logic := '0';
    signal estado_uc_s             : estado_uc_t := UC_IDLE_C;

    signal digito_binario_s : digito_t := (others => '0');
    signal digito_denso_s   : digito_t := (others => '0');

    signal resultado_valido_s : std_logic := '0';
    signal classificadores_concordam_s : std_logic := '0';

    constant TB_VGA_LOG_PATH_C : string := "python/sim_logs/session_20260612_135332/vga_log.txt";

    signal pixel_tick_capture_s : std_logic := '0';
    signal x_capture_s          : vga_coord_t := (others => '0');
    signal y_capture_s          : vga_coord_t := (others => '0');
    signal video_on_capture_s   : std_logic := '0';

    constant FRAME_EVT_0002_PAYLOAD_C : uart_frame_payload_t := (
        0 => x"00", 1 => x"00", 2 => x"00", 3 => x"00", 4 => x"00", 5 => x"00",
        6 => x"00", 7 => x"00", 8 => x"00", 9 => x"00", 10 => x"00", 11 => x"00",
        12 => x"00", 13 => x"00", 14 => x"00", 15 => x"00", 16 => x"00", 17 => x"00",
        18 => x"01", 19 => x"0F", 20 => x"00", 21 => x"00", 22 => x"7B", 23 => x"FC",
        24 => x"00", 25 => x"07", 26 => x"FF", 27 => x"C0", 28 => x"00", 29 => x"FF",
        30 => x"9E", 31 => x"00", 32 => x"1E", 33 => x"F0", 34 => x"E0", 35 => x"01",
        36 => x"DE", 37 => x"0E", 38 => x"00", 39 => x"1D", 40 => x"C0", 41 => x"E0",
        42 => x"03", 43 => x"90", 44 => x"0E", 45 => x"00", 46 => x"38", 47 => x"00",
        48 => x"E0", 49 => x"03", 50 => x"80", 51 => x"0E", 52 => x"00", 53 => x"38",
        54 => x"01", 55 => x"E0", 56 => x"03", 57 => x"80", 58 => x"1C", 59 => x"00",
        60 => x"38", 61 => x"03", 62 => x"C0", 63 => x"03", 64 => x"80", 65 => x"38",
        66 => x"00", 67 => x"1C", 68 => x"07", 69 => x"80", 70 => x"01", 71 => x"E0",
        72 => x"F0", 73 => x"00", 74 => x"0F", 75 => x"1E", 76 => x"00", 77 => x"00",
        78 => x"7F", 79 => x"C0", 80 => x"00", 81 => x"03", 82 => x"F8", 83 => x"00",
        84 => x"00", 85 => x"1F", 86 => x"00", 87 => x"00", 88 => x"00", 89 => x"00",
        90 => x"00", 91 => x"00", 92 => x"00", 93 => x"00", 94 => x"00", 95 => x"00",
        96 => x"00", 97 => x"00"
    );

    constant SNAPSHOT_0000_PAYLOAD_C : uart_frame_payload_t := (
        0 => x"00", 1 => x"00", 2 => x"00", 3 => x"00", 4 => x"00", 5 => x"00",
        6 => x"00", 7 => x"00", 8 => x"00", 9 => x"00", 10 => x"00", 11 => x"00",
        12 => x"00", 13 => x"00", 14 => x"00", 15 => x"00", 16 => x"00", 17 => x"00",
        18 => x"01", 19 => x"0F", 20 => x"00", 21 => x"00", 22 => x"7B", 23 => x"FC",
        24 => x"00", 25 => x"07", 26 => x"FF", 27 => x"C0", 28 => x"00", 29 => x"FF",
        30 => x"9E", 31 => x"00", 32 => x"1E", 33 => x"F0", 34 => x"E0", 35 => x"01",
        36 => x"DE", 37 => x"0E", 38 => x"00", 39 => x"1D", 40 => x"C0", 41 => x"E0",
        42 => x"03", 43 => x"90", 44 => x"0E", 45 => x"00", 46 => x"38", 47 => x"00",
        48 => x"E0", 49 => x"03", 50 => x"80", 51 => x"0E", 52 => x"00", 53 => x"38",
        54 => x"01", 55 => x"E0", 56 => x"03", 57 => x"80", 58 => x"1C", 59 => x"00",
        60 => x"38", 61 => x"03", 62 => x"C0", 63 => x"03", 64 => x"80", 65 => x"38",
        66 => x"00", 67 => x"1C", 68 => x"07", 69 => x"80", 70 => x"01", 71 => x"E0",
        72 => x"F0", 73 => x"00", 74 => x"0F", 75 => x"1E", 76 => x"00", 77 => x"00",
        78 => x"7F", 79 => x"C0", 80 => x"00", 81 => x"03", 82 => x"F8", 83 => x"00",
        84 => x"00", 85 => x"1F", 86 => x"00", 87 => x"00", 88 => x"00", 89 => x"00",
        90 => x"00", 91 => x"00", 92 => x"00", 93 => x"00", 94 => x"00", 95 => x"00",
        96 => x"00", 97 => x"00"
    );
    constant SNAPSHOT_0000_IMAGE_C : imagem_mnist_t :=
        tb_payload_to_image(SNAPSHOT_0000_PAYLOAD_C);

    constant FRAME_EVT_0006_PAYLOAD_C : uart_frame_payload_t := (
        0 => x"00", 1 => x"00", 2 => x"00", 3 => x"00", 4 => x"00", 5 => x"00",
        6 => x"00", 7 => x"00", 8 => x"00", 9 => x"00", 10 => x"00", 11 => x"00",
        12 => x"00", 13 => x"00", 14 => x"00", 15 => x"03", 16 => x"80", 17 => x"00",
        18 => x"00", 19 => x"38", 20 => x"00", 21 => x"00", 22 => x"03", 23 => x"80",
        24 => x"00", 25 => x"00", 26 => x"78", 27 => x"00", 28 => x"00", 29 => x"07",
        30 => x"80", 31 => x"00", 32 => x"00", 33 => x"70", 34 => x"00", 35 => x"00",
        36 => x"0F", 37 => x"00", 38 => x"00", 39 => x"01", 40 => x"F0", 41 => x"00",
        42 => x"00", 43 => x"1F", 44 => x"00", 45 => x"00", 46 => x"00", 47 => x"F0",
        48 => x"00", 49 => x"00", 50 => x"07", 51 => x"00", 52 => x"00", 53 => x"00",
        54 => x"E0", 55 => x"00", 56 => x"00", 57 => x"0E", 58 => x"00", 59 => x"00",
        60 => x"00", 61 => x"E0", 62 => x"00", 63 => x"00", 64 => x"0E", 65 => x"00",
        66 => x"00", 67 => x"00", 68 => x"E0", 69 => x"00", 70 => x"00", 71 => x"1E",
        72 => x"00", 73 => x"00", 74 => x"03", 75 => x"F0", 76 => x"00", 77 => x"00",
        78 => x"3F", 79 => x"80", 80 => x"00", 81 => x"00", 82 => x"38", 83 => x"00",
        84 => x"00", 85 => x"00", 86 => x"00", 87 => x"00", 88 => x"00", 89 => x"00",
        90 => x"00", 91 => x"00", 92 => x"00", 93 => x"00", 94 => x"00", 95 => x"00",
        96 => x"00", 97 => x"00"
    );

    constant SNAPSHOT_0001_PAYLOAD_C : uart_frame_payload_t := (
        0 => x"00", 1 => x"00", 2 => x"00", 3 => x"00", 4 => x"00", 5 => x"00",
        6 => x"00", 7 => x"00", 8 => x"00", 9 => x"00", 10 => x"00", 11 => x"00",
        12 => x"00", 13 => x"00", 14 => x"00", 15 => x"03", 16 => x"80", 17 => x"00",
        18 => x"00", 19 => x"38", 20 => x"00", 21 => x"00", 22 => x"03", 23 => x"80",
        24 => x"00", 25 => x"00", 26 => x"78", 27 => x"00", 28 => x"00", 29 => x"07",
        30 => x"80", 31 => x"00", 32 => x"00", 33 => x"70", 34 => x"00", 35 => x"00",
        36 => x"0F", 37 => x"00", 38 => x"00", 39 => x"01", 40 => x"F0", 41 => x"00",
        42 => x"00", 43 => x"1F", 44 => x"00", 45 => x"00", 46 => x"00", 47 => x"F0",
        48 => x"00", 49 => x"00", 50 => x"07", 51 => x"00", 52 => x"00", 53 => x"00",
        54 => x"E0", 55 => x"00", 56 => x"00", 57 => x"0E", 58 => x"00", 59 => x"00",
        60 => x"00", 61 => x"E0", 62 => x"00", 63 => x"00", 64 => x"0E", 65 => x"00",
        66 => x"00", 67 => x"00", 68 => x"E0", 69 => x"00", 70 => x"00", 71 => x"1E",
        72 => x"00", 73 => x"00", 74 => x"03", 75 => x"F0", 76 => x"00", 77 => x"00",
        78 => x"3F", 79 => x"80", 80 => x"00", 81 => x"00", 82 => x"38", 83 => x"00",
        84 => x"00", 85 => x"00", 86 => x"00", 87 => x"00", 88 => x"00", 89 => x"00",
        90 => x"00", 91 => x"00", 92 => x"00", 93 => x"00", 94 => x"00", 95 => x"00",
        96 => x"00", 97 => x"00"
    );
    constant SNAPSHOT_0001_IMAGE_C : imagem_mnist_t :=
        tb_payload_to_image(SNAPSHOT_0001_PAYLOAD_C);

    constant FRAME_EVT_0010_PAYLOAD_C : uart_frame_payload_t := (
        0 => x"00", 1 => x"00", 2 => x"00", 3 => x"00", 4 => x"00", 5 => x"00",
        6 => x"00", 7 => x"00", 8 => x"00", 9 => x"00", 10 => x"00", 11 => x"00",
        12 => x"3E", 13 => x"00", 14 => x"00", 15 => x"0F", 16 => x"F0", 17 => x"00",
        18 => x"03", 19 => x"FF", 20 => x"00", 21 => x"00", 22 => x"7E", 23 => x"70",
        24 => x"00", 25 => x"03", 26 => x"87", 27 => x"00", 28 => x"00", 29 => x"00",
        30 => x"70", 31 => x"00", 32 => x"00", 33 => x"07", 34 => x"00", 35 => x"00",
        36 => x"00", 37 => x"70", 38 => x"00", 39 => x"00", 40 => x"07", 41 => x"00",
        42 => x"00", 43 => x"00", 44 => x"F0", 45 => x"00", 46 => x"00", 47 => x"0E",
        48 => x"00", 49 => x"00", 50 => x"C1", 51 => x"E0", 52 => x"00", 53 => x"1F",
        54 => x"3C", 55 => x"00", 56 => x"01", 57 => x"FF", 58 => x"80", 59 => x"00",
        60 => x"3F", 61 => x"F0", 62 => x"00", 63 => x"03", 64 => x"BF", 65 => x"03",
        66 => x"00", 67 => x"3B", 68 => x"F0", 69 => x"70", 70 => x"03", 71 => x"FF",
        72 => x"CE", 73 => x"00", 74 => x"3F", 75 => x"3E", 76 => x"00", 77 => x"01",
        78 => x"E1", 79 => x"E0", 80 => x"00", 81 => x"00", 82 => x"00", 83 => x"00",
        84 => x"00", 85 => x"00", 86 => x"00", 87 => x"00", 88 => x"00", 89 => x"00",
        90 => x"00", 91 => x"00", 92 => x"00", 93 => x"00", 94 => x"00", 95 => x"00",
        96 => x"00", 97 => x"00"
    );

    constant SNAPSHOT_0002_PAYLOAD_C : uart_frame_payload_t := (
        0 => x"00", 1 => x"00", 2 => x"00", 3 => x"00", 4 => x"00", 5 => x"00",
        6 => x"00", 7 => x"00", 8 => x"00", 9 => x"00", 10 => x"00", 11 => x"00",
        12 => x"3E", 13 => x"00", 14 => x"00", 15 => x"0F", 16 => x"F0", 17 => x"00",
        18 => x"03", 19 => x"FF", 20 => x"00", 21 => x"00", 22 => x"7E", 23 => x"70",
        24 => x"00", 25 => x"03", 26 => x"87", 27 => x"00", 28 => x"00", 29 => x"00",
        30 => x"70", 31 => x"00", 32 => x"00", 33 => x"07", 34 => x"00", 35 => x"00",
        36 => x"00", 37 => x"70", 38 => x"00", 39 => x"00", 40 => x"07", 41 => x"00",
        42 => x"00", 43 => x"00", 44 => x"F0", 45 => x"00", 46 => x"00", 47 => x"0E",
        48 => x"00", 49 => x"00", 50 => x"C1", 51 => x"E0", 52 => x"00", 53 => x"1F",
        54 => x"3C", 55 => x"00", 56 => x"01", 57 => x"FF", 58 => x"80", 59 => x"00",
        60 => x"3F", 61 => x"F0", 62 => x"00", 63 => x"03", 64 => x"BF", 65 => x"03",
        66 => x"00", 67 => x"3B", 68 => x"F0", 69 => x"70", 70 => x"03", 71 => x"FF",
        72 => x"CE", 73 => x"00", 74 => x"3F", 75 => x"3E", 76 => x"00", 77 => x"01",
        78 => x"E1", 79 => x"E0", 80 => x"00", 81 => x"00", 82 => x"00", 83 => x"00",
        84 => x"00", 85 => x"00", 86 => x"00", 87 => x"00", 88 => x"00", 89 => x"00",
        90 => x"00", 91 => x"00", 92 => x"00", 93 => x"00", 94 => x"00", 95 => x"00",
        96 => x"00", 97 => x"00"
    );
    constant SNAPSHOT_0002_IMAGE_C : imagem_mnist_t :=
        tb_payload_to_image(SNAPSHOT_0002_PAYLOAD_C);

    function count_pixels(image : imagem_mnist_t) return natural is
        variable total_v : natural := 0;
    begin
        for i in image'range loop
            if image(i) = '1' then
                total_v := total_v + 1;
            end if;
        end loop;

        return total_v;
    end function;

    procedure report_signal_change(
        name      : in string;
        old_value : in std_logic;
        new_value : in std_logic
    ) is
    begin
        if old_value /= new_value then
            report "MON " & name & ": " & std_logic'image(old_value) &
                   " -> " & std_logic'image(new_value)
                severity note;
        end if;
    end procedure;

begin

    clock_50 <= not clock_50 after TB_CLK_PERIOD_C / 2;

    reset_sistema_s <= '0';

    u_interface_entrada : entity work.interface_entrada
        port map (
            clock              => clock_50,
            escreve            => escreve,
            apaga              => apaga,
            classifica         => classifica,
            escrita_habilitada => escrita_habilitada_s,
            limpa_canvas_pulso => limpa_canvas_pulso_s,
            classifica_pulso   => classifica_pulso_s
        );

    u_uart_frontend : entity work.uart_frontend
        port map (
            clock                  => clock_50,
            reset                  => reset_sistema_s,
            uart_rx_serial         => uart_rx_serial,
            uart_tx_serial         => uart_tx_serial,
            frame_recebido         => frame_recebido_s,
            frame_recebido_valido  => frame_recebido_valido_s,
            uart_recebendo         => uart_recebendo_s,
            pacote_ok_pulso        => pacote_ok_pulso_s,
            pacote_erro_pulso      => pacote_erro_pulso_s,
            erro_codigo            => erro_codigo_s,
            seq_ultimo             => seq_ultimo_s
        );

    u_mnist_canvas : entity work.mnist_canvas
        port map (
            clock                  => clock_50,
            reset                  => reset_sistema_s,
            limpa_canvas_pulso     => limpa_canvas_pulso_s,
            escrita_habilitada     => escrita_habilitada_s,
            frame_recebido         => frame_recebido_s,
            frame_recebido_valido  => frame_recebido_valido_s,
            imagem_atual           => imagem_canvas_s,
            imagem_valida          => imagem_valida_s,
            imagem_alterada_pulso  => imagem_alterada_pulso_s
        );

    u_mnist_uc : entity work.mnist_uc
        port map (
            clock                  => clock_50,
            reset                  => reset_sistema_s,
            classifica_pulso       => classifica_pulso_s,
            limpa_canvas_pulso     => limpa_canvas_pulso_s,
            imagem_alterada_pulso  => imagem_alterada_pulso_s,
            escrita_habilitada     => escrita_habilitada_s,
            imagem_valida          => imagem_valida_s,
            denso_pronto           => denso_pronto_s,
            inicia_denso           => inicia_denso_s,
            registra_resultado     => registra_resultado_s,
            limpa_resultado        => limpa_resultado_s,
            classificacao_ocupada  => classificacao_ocupada_s,
            resultado_pendente     => resultado_pendente_s,
            estado_uc              => estado_uc_s
        );

    u_mnist_fd : entity work.mnist_fd
        port map (
            clock                    => clock_50,
            reset                    => reset_sistema_s,
            imagem                   => imagem_canvas_s,
            inicia_denso             => inicia_denso_s,
            registra_resultado       => registra_resultado_s,
            limpa_resultado          => limpa_resultado_s,
            denso_pronto             => denso_pronto_s,
            digito_binario           => digito_binario_s,
            digito_denso             => digito_denso_s,
            resultado_valido         => resultado_valido_s,
            classificadores_concordam => classificadores_concordam_s
        );

    u_interface_saida : entity work.interface_saida
        port map (
            clock                    => clock_50,
            reset                    => reset_sistema_s,
            limpa_canvas_pulso       => limpa_canvas_pulso_s,
            escrita_habilitada       => escrita_habilitada_s,
            imagem_valida            => imagem_valida_s,
            uart_recebendo           => uart_recebendo_s,
            pacote_ok_pulso          => pacote_ok_pulso_s,
            pacote_erro_pulso        => pacote_erro_pulso_s,
            erro_codigo              => erro_codigo_s,
            classificacao_ocupada    => classificacao_ocupada_s,
            resultado_valido         => resultado_valido_s,
            classificadores_concordam => classificadores_concordam_s,
            digito_binario           => digito_binario_s,
            digito_denso             => digito_denso_s,
            estado_uc                => estado_uc_s,
            ledr                     => ledr,
            hex0                     => hex0,
            hex1                     => hex1,
            hex2                     => hex2,
            hex3                     => hex3,
            hex4                     => hex4,
            hex5                     => hex5
        );

    u_vga_top : entity work.vga_top
        port map (
            clock_50                 => clock_50,
            reset                    => reset_sistema_s,
            imagem                   => imagem_canvas_s,
            escrita_habilitada       => escrita_habilitada_s,
            imagem_valida            => imagem_valida_s,
            uart_recebendo           => uart_recebendo_s,
            pacote_ok_pulso          => pacote_ok_pulso_s,
            pacote_erro_pulso        => pacote_erro_pulso_s,
            erro_codigo              => erro_codigo_s,
            classificacao_ocupada    => classificacao_ocupada_s,
            resultado_valido         => resultado_valido_s,
            classificadores_concordam => classificadores_concordam_s,
            digito_binario           => digito_binario_s,
            digito_denso             => digito_denso_s,
            estado_uc                => estado_uc_s,
            vga_r                    => vga_r,
            vga_g                    => vga_g,
            vga_b                    => vga_b,
            vga_hs                   => vga_hs,
            vga_vs                   => vga_vs
        );

    u_vga_capture_clock : entity work.divisor_clock_25mhz
        port map (
            clock_50      => clock_50,
            reset         => reset_sistema_s,
            pixel_tick_25 => pixel_tick_capture_s
        );

    u_vga_capture_sync : entity work.vga_sync_640x480
        port map (
            clock      => clock_50,
            reset      => reset_sistema_s,
            pixel_tick => pixel_tick_capture_s,
            x_pixel    => x_capture_s,
            y_pixel    => y_capture_s,
            video_on   => video_on_capture_s,
            hsync      => open,
            vsync      => open
        );

    stim : process
        variable expected_canvas_v : imagem_mnist_t := (others => '0');
        variable escreve_model_v : std_logic := '0';

        file vga_log_file : text open write_mode is TB_VGA_LOG_PATH_C;

        function decimal_digit_char(value : natural) return character is
        begin
            case value is
                when 0 => return '0';
                when 1 => return '1';
                when 2 => return '2';
                when 3 => return '3';
                when 4 => return '4';
                when 5 => return '5';
                when 6 => return '6';
                when 7 => return '7';
                when 8 => return '8';
                when 9 => return '9';
                when others => return '?';
            end case;
        end function;

        function hex_digit_char(value : std_logic_vector(3 downto 0)) return character is
            variable index_v : natural := to_integer(unsigned(value));
        begin
            case index_v is
                when 0  => return '0';
                when 1  => return '1';
                when 2  => return '2';
                when 3  => return '3';
                when 4  => return '4';
                when 5  => return '5';
                when 6  => return '6';
                when 7  => return '7';
                when 8  => return '8';
                when 9  => return '9';
                when 10 => return 'A';
                when 11 => return 'B';
                when 12 => return 'C';
                when 13 => return 'D';
                when 14 => return 'E';
                when 15 => return 'F';
                when others => return 'X';
            end case;
        end function;

        procedure write_padded_natural(
            variable row_v : inout line;
            value          : in natural;
            width          : in positive
        ) is
            variable divisor_v : natural := 1;
            variable digit_v   : natural := 0;
        begin
            for i in 2 to width loop
                divisor_v := divisor_v * 10;
            end loop;

            for i in 1 to width loop
                digit_v := (value / divisor_v) mod 10;
                write(row_v, decimal_digit_char(digit_v));
                if divisor_v > 1 then
                    divisor_v := divisor_v / 10;
                end if;
            end loop;
        end procedure;

        procedure write_rgb444(
            variable row_v : inout line;
            red            : in std_logic_vector(3 downto 0);
            green          : in std_logic_vector(3 downto 0);
            blue           : in std_logic_vector(3 downto 0)
        ) is
        begin
            write(row_v, hex_digit_char(red));
            write(row_v, hex_digit_char(green));
            write(row_v, hex_digit_char(blue));
        end procedure;

        procedure wait_for_visible_vga_pixel is
        begin
            loop
                wait until rising_edge(clock_50);
                wait for 1 ns;
                exit when pixel_tick_capture_s = '1' and video_on_capture_s = '1';
            end loop;
        end procedure;

        procedure capture_vga_snapshot(
            kind     : in string;
            event_id : in natural
        ) is
            variable line_v : line;
        begin
            report "VGA aguardando snapshot " & kind & " evento " &
                   integer'image(event_id)
                severity note;

            loop
                wait_for_visible_vga_pixel;
                exit when to_integer(x_capture_s) = 0 and
                          to_integer(y_capture_s) = 0;
            end loop;

            write(line_v, string'("BEGIN_SNAPSHOT kind="));
            write(line_v, kind);
            write(line_v, string'(" event="));
            write_padded_natural(line_v, event_id, 4);
            write(line_v, string'(" width=640 height=480"));
            writeline(vga_log_file, line_v);

            for y in 0 to VGA_V_VISIBLE_C - 1 loop
                write(line_v, string'("ROW "));
                write_padded_natural(line_v, y, 3);

                for x in 0 to VGA_H_VISIBLE_C - 1 loop
                    write(line_v, string'(" "));
                    write_rgb444(line_v, vga_r, vga_g, vga_b);

                    if not (x = VGA_H_VISIBLE_C - 1 and
                            y = VGA_V_VISIBLE_C - 1) then
                        wait_for_visible_vga_pixel;
                    end if;
                end loop;

                writeline(vga_log_file, line_v);
            end loop;

            write(line_v, string'("END_SNAPSHOT"));
            writeline(vga_log_file, line_v);
            report "VGA snapshot " & kind & " evento " &
                   integer'image(event_id) & " salvo em " & TB_VGA_LOG_PATH_C
                severity note;
        end procedure;

        procedure observe_uart_byte(
            signal rx_serial : in std_logic;
            variable value   : out uart_byte_t;
            variable ok      : out boolean
        ) is
        begin
            ok := true;

            if rx_serial /= '0' then
                wait until rx_serial = '0';
            end if;

            wait for TB_BIT_TIME_C + TB_BIT_TIME_C / 2;

            for i in 0 to 7 loop
                value(i) := rx_serial;
                wait for TB_BIT_TIME_C;
            end loop;

            if rx_serial /= '1' then
                ok := false;
                report "OBS stop bit de uart_tx_serial nao ficou alto" severity warning;
            end if;

            wait for TB_BIT_TIME_C / 2;
        end procedure;

        procedure wait_control_sync is
        begin
            tb_wait_cycles(clock_50, TB_CONTROL_SYNC_WAIT_C);
        end procedure;

        procedure pulse_apaga(
            msg : in string
        ) is
        begin
            report "OBS " & msg & ": pulso de apaga" severity note;
            apaga <= '1';
            wait_control_sync;
            apaga <= '0';
            wait_control_sync;
        end procedure;

        procedure pulse_classifica_and_wait(
            timeout_cycles : in natural;
            msg            : in string
        ) is
            variable seen_v           : boolean := false;
            variable observed_after_v : natural := 0;
            variable elapsed_v        : natural := 0;
        begin
            report "OBS " & msg & ": pulso de classifica" severity note;
            classifica <= '1';

            for i in 1 to TB_CONTROL_SYNC_WAIT_C loop
                wait until rising_edge(clock_50);
                wait for 1 ns;

                if (not seen_v) and registra_resultado_s = '1' then
                    seen_v := true;
                    observed_after_v := elapsed_v;
                end if;

                elapsed_v := elapsed_v + 1;
            end loop;

            classifica <= '0';

            for i in 1 to TB_CONTROL_SYNC_WAIT_C + 4 loop
                wait until rising_edge(clock_50);
                wait for 1 ns;

                if (not seen_v) and registra_resultado_s = '1' then
                    seen_v := true;
                    observed_after_v := elapsed_v;
                end if;

                elapsed_v := elapsed_v + 1;
            end loop;

            if not seen_v then
                for i in 0 to timeout_cycles loop
                    wait until rising_edge(clock_50);
                    wait for 1 ns;

                    if registra_resultado_s = '1' then
                        seen_v := true;
                        observed_after_v := elapsed_v;
                        exit;
                    end if;

                    elapsed_v := elapsed_v + 1;
                end loop;
            end if;

            if seen_v then
                if TB_VERBOSE_C then
                    report "OBS " & msg & ": registra_resultado_s observado apos " &
                           integer'image(observed_after_v) & " ciclos"
                        severity note;
                end if;

                wait until rising_edge(clock_50);
                wait for 1 ns;

                if TB_VERBOSE_C then
                    report "OBS " & msg & ": resultado_valido_s=" &
                           std_logic'image(resultado_valido_s)
                        severity note;
                end if;
            else
                report "OBS " & msg & ": registra_resultado_s nao observado na janela"
                    severity warning;
            end if;
        end procedure;

        procedure set_escreve(
            value : in std_logic;
            msg   : in string
        ) is
        begin
            escreve <= value;
            wait_control_sync;
            report "OBS " & msg & ": escreve=" & std_logic'image(value)
                severity note;
            if escrita_habilitada_s /= value then
                report "OBS escreve solicitado " & std_logic'image(value) &
                       ", observado escrita_habilitada_s=" &
                       std_logic'image(escrita_habilitada_s)
                    severity warning;
            elsif TB_VERBOSE_C then
                report "OBS escreve observado escrita_habilitada_s=" &
                       std_logic'image(escrita_habilitada_s)
                    severity note;
            end if;
        end procedure;

        procedure observe_canvas(
            expected : in imagem_mnist_t;
            msg      : in string
        ) is
        begin
            report "OBS " & msg & ": pixels_esperados=" &
                   integer'image(count_pixels(expected)) &
                   " pixels_observados=" &
                   integer'image(count_pixels(imagem_canvas_s))
                severity note;

            if TB_REPORT_CANVAS_DIFFS_C and imagem_canvas_s /= expected then
                report "OBS " & msg & ": imagem_canvas_s difere do modelo JSON"
                    severity warning;
            end if;
        end procedure;

        procedure observe_classification_registered(
            timeout_cycles : in natural;
            msg            : in string
        ) is
        begin
            for i in 0 to timeout_cycles loop
                wait until rising_edge(clock_50);
                wait for 1 ns;

                if registra_resultado_s = '1' then
                    if TB_VERBOSE_C then
                        report "OBS " & msg & ": registra_resultado_s observado apos " &
                               integer'image(i) & " ciclos"
                            severity note;
                    end if;
                    wait until rising_edge(clock_50);
                    wait for 1 ns;
                    if TB_VERBOSE_C then
                        report "OBS " & msg & ": resultado_valido_s=" &
                               std_logic'image(resultado_valido_s)
                            severity note;
                    end if;
                    return;
                end if;
            end loop;

            report "OBS " & msg & ": registra_resultado_s nao observado na janela"
                severity warning;
        end procedure;

        procedure report_classification(snapshot_name : in string) is
        begin
            report "RESULTADO " & snapshot_name &
                   ": digito_binario=" & integer'image(to_integer(digito_binario_s)) &
                   ", digito_denso=" & integer'image(to_integer(digito_denso_s)) &
                   ", concordam=" & std_logic'image(classificadores_concordam_s) &
                   ", resultado_valido=" & std_logic'image(resultado_valido_s)
                severity note;
        end procedure;

        procedure send_logged_packet(
            seq     : in uart_seq_t;
            payload : in uart_frame_payload_t;
            msg     : in string
        ) is
            variable packet_v    : uart_response_packet_t := (others => (others => '0'));
            variable byte_v      : uart_byte_t := (others => '0');
            variable byte_ok_v   : boolean := true;
            variable start_seen_v : boolean := false;
            variable ok_seen_v    : boolean := false;
            variable err_seen_v   : boolean := false;
        begin
            if TB_VERBOSE_C then
                report "OBS " & msg & ": enviando pixels_payload=" &
                       integer'image(count_pixels(tb_payload_to_image(payload)))
                    severity note;
            end if;
            tb_send_uart_frame_packet(uart_rx_serial, seq, payload, x"00");

            for i in 0 to 5000 loop
                wait until rising_edge(clock_50);
                wait for 1 ns;

                if pacote_ok_pulso_s = '1' then
                    ok_seen_v := true;
                end if;

                if pacote_erro_pulso_s = '1' then
                    err_seen_v := true;
                end if;

                if ok_seen_v or err_seen_v then
                    exit;
                end if;
            end loop;

            if ok_seen_v then
                report "OBS " & msg & ": pacote recebido OK seq=0x" &
                       to_hstring(seq_ultimo_s)
                    severity note;
            elsif err_seen_v then
                report "OBS " & msg & ": pacote recebido ERRO codigo=0x" &
                       to_hstring(erro_codigo_s)
                    severity warning;
            else
                report "OBS " & msg & ": pacote nao recebido ate o timeout"
                    severity warning;
            end if;

            if seq_ultimo_s /= seq then
                report "OBS " & msg & ": seq_ultimo_s difere da seq do JSON"
                    severity warning;
            end if;

            if TB_VERBOSE_C then
                for i in 0 to 20000 loop
                    wait until rising_edge(clock_50);
                    wait for 1 ns;

                    if uart_tx_serial = '0' then
                        start_seen_v := true;
                        exit;
                    end if;
                end loop;

                if start_seen_v then
                    for i in packet_v'range loop
                        observe_uart_byte(uart_tx_serial, byte_v, byte_ok_v);
                        packet_v(i) := byte_v;
                        if not byte_ok_v then
                            report "OBS " & msg & ": byte UART TX " &
                                   integer'image(i) & " teve aviso de frame"
                                severity warning;
                        end if;
                    end loop;

                    report "OBS " & msg & ": resposta UART TX cmd=0x" &
                           to_hstring(packet_v(2)) & " seq=0x" &
                           to_hstring(packet_v(5)) & " erro=0x" &
                           to_hstring(packet_v(6)) & " checksum=0x" &
                           to_hstring(packet_v(7))
                        severity note;
                else
                    report "OBS " & msg & ": nenhuma resposta UART TX observada"
                        severity warning;
                end if;
            end if;

            tb_wait_cycles(clock_50, TB_POST_PACKET_WAIT_C);
        end procedure;

    begin
        report "tb_mnist_top inicio da sessao: python/sim_logs/session_20260612_135332/session.json" severity note;
        escreve <= '0';
        apaga <= '0';
        classifica <= '0';
        uart_rx_serial <= '1';
        tb_wait_cycles(clock_50, 10);

        observe_canvas(expected_canvas_v, "estado inicial");

        -- evento 0: escreve = 0
        set_escreve('0', "evento 0 escreve");
        escreve_model_v := '0';

        -- evento 1: escreve = 1
        set_escreve('1', "evento 1 escreve");
        escreve_model_v := '1';

        -- evento 2: pacote UART frame SEQ=0x00
        send_logged_packet(x"00", FRAME_EVT_0002_PAYLOAD_C, "evento 2 UART SEQ 0x00");
        if escreve_model_v = '1' then
            expected_canvas_v := tb_payload_to_image(FRAME_EVT_0002_PAYLOAD_C);
            observe_canvas(expected_canvas_v, "evento 2 UART com escreve=1");
            if imagem_valida_s /= '1' then
                report "OBS evento 2: imagem_valida_s nao esta alto apos escrita habilitada"
                    severity warning;
            end if;
        else
            observe_canvas(expected_canvas_v, "evento 2 UART com escreve=0");
        end if;

        -- evento 3: captura 0
        observe_canvas(SNAPSHOT_0000_IMAGE_C, "captura 0 canvas");
        if TB_VERBOSE_C then
            report "captura 0 PNG: python/sim_logs/session_20260612_135332/snapshots/snapshot_0000.png" severity note;
        end if;

        -- evento 4: classifica
        pulse_classifica_and_wait(TB_RESULT_TIMEOUT_C, "evento 4 classifica");
        report_classification("captura 0: python/sim_logs/session_20260612_135332/snapshots/snapshot_0000.png");
        capture_vga_snapshot("classifica", 4);

        -- evento 5: apaga
        pulse_apaga("evento 5 apaga");
        expected_canvas_v := (others => '0');
        observe_canvas(expected_canvas_v, "evento 5 apaga");
        if imagem_valida_s /= '0' then
            report "OBS evento 5: imagem_valida_s nao esta baixo apos apaga"
                severity warning;
        end if;
        capture_vga_snapshot("apaga", 5);

        -- evento 6: pacote UART frame SEQ=0x01
        send_logged_packet(x"01", FRAME_EVT_0006_PAYLOAD_C, "evento 6 UART SEQ 0x01");
        if escreve_model_v = '1' then
            expected_canvas_v := tb_payload_to_image(FRAME_EVT_0006_PAYLOAD_C);
            observe_canvas(expected_canvas_v, "evento 6 UART com escreve=1");
            if imagem_valida_s /= '1' then
                report "OBS evento 6: imagem_valida_s nao esta alto apos escrita habilitada"
                    severity warning;
            end if;
        else
            observe_canvas(expected_canvas_v, "evento 6 UART com escreve=0");
        end if;

        -- evento 7: captura 1
        observe_canvas(SNAPSHOT_0001_IMAGE_C, "captura 1 canvas");
        if TB_VERBOSE_C then
            report "captura 1 PNG: python/sim_logs/session_20260612_135332/snapshots/snapshot_0001.png" severity note;
        end if;

        -- evento 8: classifica
        pulse_classifica_and_wait(TB_RESULT_TIMEOUT_C, "evento 8 classifica");
        report_classification("captura 1: python/sim_logs/session_20260612_135332/snapshots/snapshot_0001.png");
        capture_vga_snapshot("classifica", 8);

        -- evento 9: apaga
        pulse_apaga("evento 9 apaga");
        expected_canvas_v := (others => '0');
        observe_canvas(expected_canvas_v, "evento 9 apaga");
        if imagem_valida_s /= '0' then
            report "OBS evento 9: imagem_valida_s nao esta baixo apos apaga"
                severity warning;
        end if;
        capture_vga_snapshot("apaga", 9);

        -- evento 10: pacote UART frame SEQ=0x02
        send_logged_packet(x"02", FRAME_EVT_0010_PAYLOAD_C, "evento 10 UART SEQ 0x02");
        if escreve_model_v = '1' then
            expected_canvas_v := tb_payload_to_image(FRAME_EVT_0010_PAYLOAD_C);
            observe_canvas(expected_canvas_v, "evento 10 UART com escreve=1");
            if imagem_valida_s /= '1' then
                report "OBS evento 10: imagem_valida_s nao esta alto apos escrita habilitada"
                    severity warning;
            end if;
        else
            observe_canvas(expected_canvas_v, "evento 10 UART com escreve=0");
        end if;

        -- evento 11: captura 2
        observe_canvas(SNAPSHOT_0002_IMAGE_C, "captura 2 canvas");
        if TB_VERBOSE_C then
            report "captura 2 PNG: python/sim_logs/session_20260612_135332/snapshots/snapshot_0002.png" severity note;
        end if;

        -- evento 12: classifica
        pulse_classifica_and_wait(TB_RESULT_TIMEOUT_C, "evento 12 classifica");
        report_classification("captura 2: python/sim_logs/session_20260612_135332/snapshots/snapshot_0002.png");
        capture_vga_snapshot("classifica", 12);

        -- evento 13: apaga
        pulse_apaga("evento 13 apaga");
        expected_canvas_v := (others => '0');
        observe_canvas(expected_canvas_v, "evento 13 apaga");
        if imagem_valida_s /= '0' then
            report "OBS evento 13: imagem_valida_s nao esta baixo apos apaga"
                severity warning;
        end if;
        capture_vga_snapshot("apaga", 13);

        report "tb_mnist_top concluido" severity note;
        stop;
        wait;
    end process;

end architecture sim;

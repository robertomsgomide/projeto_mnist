-------------------------------------------------------------------------------
-- Arquivo   : mnist_top.vhd
-------------------------------------------------------------------------------
-- Descricao : entidade de topo estrutural do classificador MNIST com entrada
--             dinamica via UART. Integra recepcao serial, buffer de frame,
--             unidade de controle, classificadores, interface VGA, LEDs e HEX.
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     18/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  versao inicial
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;

entity mnist_top is
    port (
        clock_50 : in  std_logic;

        escreve    : in std_logic;
        apaga      : in std_logic;
        classifica : in std_logic;

        uart_rx_serial : in  std_logic;
        uart_tx_serial : out std_logic;

        ledr : out led_bus_t;

        hex0 : out hex7seg_t;
        hex1 : out hex7seg_t;
        hex2 : out hex7seg_t;
        hex3 : out hex7seg_t;
        hex4 : out hex7seg_t;
        hex5 : out hex7seg_t;

        vga_r  : out std_logic_vector(3 downto 0);
        vga_g  : out std_logic_vector(3 downto 0);
        vga_b  : out std_logic_vector(3 downto 0);
        vga_hs : out std_logic;
        vga_vs : out std_logic
    );
end entity mnist_top;

architecture estrutural of mnist_top is

    component interface_entrada is
        port (
            clock : in std_logic;

            escreve    : in std_logic;
            apaga      : in std_logic;
            classifica : in std_logic;

            escrita_habilitada : out std_logic;
            limpa_canvas_pulso : out std_logic;
            classifica_pulso   : out std_logic
        );
    end component;

    component uart_frontend is
        port (
            clock : in std_logic;
            reset : in std_logic;

            uart_rx_serial : in  std_logic;
            uart_tx_serial : out std_logic;

            frame_recebido        : out imagem_mnist_t;
            frame_recebido_valido : out std_logic;

            uart_recebendo    : out std_logic;
            pacote_ok_pulso   : out std_logic;
            pacote_erro_pulso : out std_logic;
            erro_codigo       : out uart_erro_t;

            seq_ultimo : out uart_seq_t
        );
    end component;

    component mnist_canvas is
        port (
            clock : in std_logic;
            reset : in std_logic;

            limpa_canvas_pulso : in std_logic;
            escrita_habilitada : in std_logic;

            frame_recebido        : in imagem_mnist_t;
            frame_recebido_valido : in std_logic;

            imagem_atual          : out imagem_mnist_t;
            imagem_valida         : out std_logic;
            imagem_alterada_pulso : out std_logic
        );
    end component;

    component mnist_uc is
        port (
            clock : in std_logic;
            reset : in std_logic;

            classifica_pulso      : in std_logic;
            limpa_canvas_pulso    : in std_logic;
            imagem_alterada_pulso : in std_logic;
            escrita_habilitada    : in std_logic;
            imagem_valida         : in std_logic;

            denso_pronto : in std_logic;

            inicia_denso       : out std_logic;
            registra_resultado : out std_logic;
            limpa_resultado    : out std_logic;

            classificacao_ocupada : out std_logic;
            resultado_pendente    : out std_logic;

            estado_uc : out estado_uc_t
        );
    end component;

    component mnist_fd is
        port (
            clock : in std_logic;
            reset : in std_logic;

            imagem : in imagem_mnist_t;

            inicia_denso       : in std_logic;
            registra_resultado : in std_logic;
            limpa_resultado    : in std_logic;

            denso_pronto : out std_logic;

            digito_binario : out digito_t;
            digito_denso   : out digito_t;

            resultado_valido : out std_logic;
            classificadores_concordam : out std_logic
        );
    end component;

    component interface_saida is
        port (
            clock : in std_logic;
            reset : in std_logic;

            limpa_canvas_pulso : in std_logic;

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

            ledr : out led_bus_t;

            hex0 : out hex7seg_t;
            hex1 : out hex7seg_t;
            hex2 : out hex7seg_t;
            hex3 : out hex7seg_t;
            hex4 : out hex7seg_t;
            hex5 : out hex7seg_t
        );
    end component;

    component vga_top is
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
    end component;

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

begin

    reset_sistema_s <= '0';

    u_interface_entrada : interface_entrada
        port map (
            clock               => clock_50,
            escreve             => escreve,
            apaga               => apaga,
            classifica          => classifica,
            escrita_habilitada  => escrita_habilitada_s,
            limpa_canvas_pulso  => limpa_canvas_pulso_s,
            classifica_pulso    => classifica_pulso_s
        );

    u_uart_frontend : uart_frontend
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

    u_mnist_canvas : mnist_canvas
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

    u_mnist_uc : mnist_uc
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

    u_mnist_fd : mnist_fd
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

    u_interface_saida : interface_saida
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

    u_vga_top : vga_top
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

end architecture estrutural;

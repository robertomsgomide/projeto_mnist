-------------------------------------------------------------------------------
-- Arquivo   : classificador_denso_seq.vhd
-------------------------------------------------------------------------------
-- Descricao : classificador denso sequencial.
--             A imagem tem 784 pixels binarios; cada digito tem 784 pesos
--             inteiros de 8 bits e um bias quantizado. A cada ciclo, o circuito
--             le o proximo pixel; se o pixel vale 1, soma o peso correspondente
--             aos acumuladores dos dez digitos. Ao final, escolhe o maior
--             acumulador.
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     18/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  versao inicial
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;
use work.bias_densos_pkg.all;

entity classificador_denso_seq is
    port (
        clock : in std_logic;
        reset : in std_logic;

        iniciar : in std_logic;

        imagem : in imagem_mnist_t;

        pronto       : out std_logic;
        digito_saida : out digito_t
    );
end entity classificador_denso_seq;

architecture arch of classificador_denso_seq is
    type estado_t is (
        S_IDLE,
        S_PROCESSA,
        S_FINALIZA,
        S_ARGMAX_INICIA,
        S_ARGMAX_AGUARDA,
        S_PRONTO
    );

    signal estado      : estado_t := S_IDLE;
    signal prox_estado : estado_t := S_IDLE;

    signal limpa_int        : std_logic;
    signal habilita_cont    : std_logic;
    signal habilita_acc     : std_logic;
    signal pronto_int       : std_logic;

    signal iniciar_argmax_s : std_logic;
    signal pronto_argmax_s  : std_logic;

    signal contagem_int : pixel_addr_t;
    signal fim_int      : std_logic;

    signal pesos_int    : peso10_array_t;
    signal scores_int   : score_denso_array_t;
    signal digito_max_s : digito_t;

    signal pixel_ativo_d1 : std_logic := '0';
    signal habilita_d1    : std_logic := '0';
begin
    u_contador_pixel : entity work.contador_pixel
        port map (
            clock    => clock,
            reset    => reset,
            limpa    => limpa_int,
            habilita => habilita_cont,
            contagem => contagem_int,
            fim      => fim_int
        );

    u_rom_pesos : entity work.rom_pesos_densos
        port map (
            clock          => clock,
            endereco_pixel => contagem_int,
            pesos_pixel    => pesos_int
        );

    process(clock, reset)
    begin
        if reset = '1' then
            pixel_ativo_d1 <= '0';
            habilita_d1    <= '0';

        elsif rising_edge(clock) then
            pixel_ativo_d1 <= imagem(to_integer(contagem_int));
            habilita_d1    <= habilita_acc;
        end if;
    end process;

    u_acc : entity work.acumuladores_digitos
        port map (
            clock       => clock,
            reset       => reset,
            limpa       => limpa_int,
            habilita    => habilita_d1,
            pixel_ativo => pixel_ativo_d1,
            pesos       => pesos_int,
            biases      => BIAS_DENSOS_C,
            scores      => scores_int
        );

    u_argmax : entity work.argmax10_signed
        port map (
            clock      => clock,
            reset      => reset,
            iniciar    => iniciar_argmax_s,
            scores     => scores_int,
            ocupado    => open,
            pronto     => pronto_argmax_s,
            digito_max => digito_max_s,
            score_max  => open
        );

    process(clock, reset)
    begin
        if reset = '1' then
            estado <= S_IDLE;

        elsif rising_edge(clock) then
            estado <= prox_estado;
        end if;
    end process;

    process(estado, iniciar, fim_int, pronto_argmax_s)
    begin
        prox_estado <= estado;

        case estado is
            when S_IDLE =>
                if iniciar = '1' then
                    prox_estado <= S_PROCESSA;
                end if;

            when S_PROCESSA =>
                if fim_int = '1' then
                    prox_estado <= S_FINALIZA;
                end if;

            when S_FINALIZA =>
                prox_estado <= S_ARGMAX_INICIA;

            when S_ARGMAX_INICIA =>
                prox_estado <= S_ARGMAX_AGUARDA;

            when S_ARGMAX_AGUARDA =>
                if pronto_argmax_s = '1' then
                    prox_estado <= S_PRONTO;
                end if;

            when S_PRONTO =>
                if iniciar = '1' then
                    prox_estado <= S_PROCESSA;
                end if;
        end case;
    end process;

    limpa_int <= '1' when
                 ((estado = S_IDLE   and iniciar = '1') or
                  (estado = S_PRONTO and iniciar = '1'))
                 else '0';

    habilita_cont <= '1' when estado = S_PROCESSA else '0';
    habilita_acc  <= '1' when estado = S_PROCESSA else '0';

    iniciar_argmax_s <= '1' when estado = S_ARGMAX_INICIA else '0';

    pronto_int <= '1' when estado = S_PRONTO else '0';

    pronto       <= pronto_int;
    digito_saida <= digito_max_s;
end architecture arch;

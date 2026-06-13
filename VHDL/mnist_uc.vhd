-------------------------------------------------------------------------------
-- Arquivo   : mnist_uc.vhd
-------------------------------------------------------------------------------
-- Descricao : unidade de controle do classificador MNIST com entrada dinamica.
--             Coordena a recepcao de nova imagem, o disparo da classificacao,
--             a espera pelo classificador denso e o registro dos resultados.
--             classifica pode solicitar classificacao durante a escrita; se a
--             imagem mudar durante a classificacao, imagem_alterada_pulso
--             descarta o resultado em andamento.
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     18/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  versao inicial
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;

entity mnist_uc is
    port (
        clock : in std_logic;
        reset : in std_logic;

        classifica_pulso   : in std_logic;
        limpa_canvas_pulso : in std_logic;
        imagem_alterada_pulso : in std_logic;
        escrita_habilitada : in std_logic;
        imagem_valida      : in std_logic;

        denso_pronto : in std_logic;

        inicia_denso       : out std_logic;
        registra_resultado : out std_logic;
        limpa_resultado    : out std_logic;

        classificacao_ocupada : out std_logic;
        resultado_pendente    : out std_logic;

        estado_uc : out estado_uc_t
    );
end entity mnist_uc;

architecture arch of mnist_uc is

    type estado_int_t is (
        S_IDLE,
        S_CLASSIFICA,
        S_AGUARDA,
        S_REGISTRA,
        S_PRONTO
    );

    signal estado_s : estado_int_t := S_IDLE;
    signal descarta_resultado_s : std_logic := '0';

    signal solicita_classificacao_s : std_logic;
    signal limpa_resultado_s        : std_logic;

begin

    solicita_classificacao_s <= '1' when
        classifica_pulso = '1' and
        imagem_valida = '1'
        else '0';

    limpa_resultado_s <= limpa_canvas_pulso or imagem_alterada_pulso;

    process(clock, reset)
    begin
        if reset = '1' then
            estado_s              <= S_IDLE;
            descarta_resultado_s  <= '0';

        elsif rising_edge(clock) then
            if limpa_resultado_s = '1' then
                if estado_s = S_CLASSIFICA or estado_s = S_AGUARDA then
                    estado_s             <= S_AGUARDA;
                    descarta_resultado_s <= '1';
                else
                    estado_s             <= S_IDLE;
                    descarta_resultado_s <= '0';
                end if;

            else
                case estado_s is
                    when S_IDLE =>
                        descarta_resultado_s <= '0';

                        if solicita_classificacao_s = '1' then
                            estado_s <= S_CLASSIFICA;
                        end if;

                    when S_CLASSIFICA =>
                        estado_s <= S_AGUARDA;

                    when S_AGUARDA =>
                        if denso_pronto = '1' then
                            if descarta_resultado_s = '1' then
                                estado_s             <= S_IDLE;
                                descarta_resultado_s <= '0';
                            else
                                estado_s <= S_REGISTRA;
                            end if;
                        end if;

                    when S_REGISTRA =>
                        estado_s <= S_PRONTO;

                    when S_PRONTO =>
                        descarta_resultado_s <= '0';

                        if solicita_classificacao_s = '1' then
                            estado_s <= S_CLASSIFICA;
                        end if;
                end case;
            end if;
        end if;
    end process;

    inicia_denso <= '1' when
        estado_s = S_CLASSIFICA and limpa_resultado_s = '0'
        else '0';

    registra_resultado <= '1' when
        estado_s = S_REGISTRA and limpa_resultado_s = '0'
        else '0';

    limpa_resultado <= limpa_resultado_s;

    classificacao_ocupada <= '1' when
        estado_s = S_CLASSIFICA or estado_s = S_AGUARDA
        else '0';

    resultado_pendente <= '1' when
        estado_s = S_CLASSIFICA or
        estado_s = S_AGUARDA or
        estado_s = S_REGISTRA
        else '0';

    with estado_s select
        estado_uc <= UC_IDLE_C       when S_IDLE,
                     UC_CLASSIFICA_C when S_CLASSIFICA,
                     UC_AGUARDA_C    when S_AGUARDA,
                     UC_REGISTRA_C   when S_REGISTRA,
                     UC_PRONTO_C     when S_PRONTO;

end architecture arch;

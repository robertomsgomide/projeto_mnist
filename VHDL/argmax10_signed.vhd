-------------------------------------------------------------------------------
-- Arquivo   : argmax10_signed.vhd
-------------------------------------------------------------------------------
-- Descricao : recebe dez scores com sinal e devolve o indice do maior valor
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     18/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  novo componente
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;

entity argmax10_signed is
    port (
        clock   : in std_logic;
        reset   : in std_logic;
        iniciar : in std_logic;

        scores : in score_denso_array_t;

        ocupado : out std_logic;
        pronto  : out std_logic;

        digito_max : out digito_t;
        score_max  : out score_denso_t
    );
end entity argmax10_signed;

architecture arch of argmax10_signed is

    type estado_t is (
        S_IDLE,
        S_VARRE,
        S_PRONTO
    );

    signal estado : estado_t := S_IDLE;

    signal idx_reg          : integer range 0 to NUM_DIGITOS_C-1 := 0;
    signal melhor_dig_reg   : digito_t      := (others => '0');
    signal melhor_score_reg : score_denso_t := (others => '0');

begin

    --------------------------------------------------------------------
    -- FSM sequencial do argmax
    --------------------------------------------------------------------
    process(clock, reset)
    begin
        if reset = '1' then
            estado           <= S_IDLE;
            idx_reg          <= 0;
            melhor_dig_reg   <= (others => '0');
            melhor_score_reg <= (others => '0');

        elsif rising_edge(clock) then

            case estado is

                ----------------------------------------------------------------
                -- Aguarda pulso de inicio.
                -- Ao iniciar, assume inicialmente que o digito 0 e o melhor.
                ----------------------------------------------------------------
                when S_IDLE =>
                    if iniciar = '1' then
                        melhor_score_reg <= scores(0);
                        melhor_dig_reg   <= to_unsigned(0, digito_t'length);
                        idx_reg          <= 1;
                        estado           <= S_VARRE;
                    end if;

                ----------------------------------------------------------------
                -- Varre os candidatos 1..9, um por ciclo.
                ----------------------------------------------------------------
                when S_VARRE =>
                    if scores(idx_reg) > melhor_score_reg then
                        melhor_score_reg <= scores(idx_reg);
                        melhor_dig_reg   <= to_unsigned(idx_reg, digito_t'length);
                    end if;

                    if idx_reg = NUM_DIGITOS_C-1 then
                        estado <= S_PRONTO;
                    else
                        idx_reg <= idx_reg + 1;
                    end if;

                ----------------------------------------------------------------
                -- Mantem o resultado estavel ate uma nova requisicao.
                ----------------------------------------------------------------
                when S_PRONTO =>
                    if iniciar = '1' then
                        melhor_score_reg <= scores(0);
                        melhor_dig_reg   <= to_unsigned(0, digito_t'length);
                        idx_reg          <= 1;
                        estado           <= S_VARRE;
                    end if;

            end case;
        end if;
    end process;

    --------------------------------------------------------------------
    -- Saidas
    --------------------------------------------------------------------
    ocupado    <= '1' when estado = S_VARRE   else '0';
    pronto     <= '1' when estado = S_PRONTO  else '0';

    digito_max <= melhor_dig_reg;
    score_max  <= melhor_score_reg;

end architecture arch;
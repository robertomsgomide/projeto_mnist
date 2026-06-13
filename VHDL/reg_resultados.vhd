-------------------------------------------------------------------------------
-- Arquivo   : reg_resultados.vhd
-------------------------------------------------------------------------------
-- Descricao : registrador dos resultados de classificacao. Armazena as
--             predicoes dos classificadores binario e denso, a concordancia
--             entre elas e a validade do resultado exibido.
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     18/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  versao inicial
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;

entity reg_resultados is
    port (
        clock : in std_logic;
        reset : in std_logic;

        limpa    : in std_logic;
        registra : in std_logic;

        digito_binario_in : in digito_t;
        digito_denso_in   : in digito_t;

        digito_binario_out : out digito_t;
        digito_denso_out   : out digito_t;

        resultado_valido : out std_logic;
        classificadores_concordam : out std_logic
    );
end entity reg_resultados;

architecture arch of reg_resultados is

    signal digito_binario_s : digito_t := (others => '0');
    signal digito_denso_s   : digito_t := (others => '0');

    signal resultado_valido_s : std_logic := '0';
    signal concordam_s        : std_logic := '0';

begin

    process(clock, reset)
    begin
        if reset = '1' then
            digito_binario_s      <= (others => '0');
            digito_denso_s        <= (others => '0');
            resultado_valido_s    <= '0';
            concordam_s           <= '0';

        elsif rising_edge(clock) then
            if limpa = '1' then
                digito_binario_s      <= (others => '0');
                digito_denso_s        <= (others => '0');
                resultado_valido_s    <= '0';
                concordam_s           <= '0';

            elsif registra = '1' then
                digito_binario_s      <= digito_binario_in;
                digito_denso_s        <= digito_denso_in;
                resultado_valido_s    <= '1';

                if digito_binario_in = digito_denso_in then
                    concordam_s <= '1';
                else
                    concordam_s <= '0';
                end if;
            end if;
        end if;
    end process;

    digito_binario_out <= digito_binario_s;
    digito_denso_out   <= digito_denso_s;

    resultado_valido           <= resultado_valido_s;
    classificadores_concordam  <= concordam_s;

end architecture arch;

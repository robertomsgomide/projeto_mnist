-------------------------------------------------------------------------------
-- Arquivo   : sincronizador_sinais.vhd
-------------------------------------------------------------------------------
-- Descricao : sincroniza sinais assincronos
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     01/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  novo componente
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;

entity sincronizador_sinais is
    generic (
        N_G : positive := 1
    );
    port (
        clock : in std_logic;
        reset : in std_logic;

        entrada_async : in  std_logic_vector(N_G-1 downto 0);
        saida_sync    : out std_logic_vector(N_G-1 downto 0)
    );
end entity sincronizador_sinais;

architecture arch of sincronizador_sinais is
    signal estagio_1 : std_logic_vector(N_G-1 downto 0) := (others => '0');
    signal estagio_2 : std_logic_vector(N_G-1 downto 0) := (others => '0');
begin
    process(clock, reset)
    begin
        if reset = '1' then
            estagio_1 <= (others => '0');
            estagio_2 <= (others => '0');

        elsif rising_edge(clock) then
            estagio_1 <= entrada_async;
            estagio_2 <= estagio_1;
        end if;
    end process;

    saida_sync <= estagio_2;
end architecture arch;
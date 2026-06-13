-------------------------------------------------------------------------------
-- Arquivo   : detector_borda.vhd
-------------------------------------------------------------------------------
-- Descricao : detector de borda de subida e descida
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     18/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  novo componente
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;

entity detector_borda is
    generic (
        N_G : positive := 1
    );
    port (
        clock : in std_logic;
        reset : in std_logic;

        entrada : in std_logic_vector(N_G-1 downto 0);

        pulso_subida  : out std_logic_vector(N_G-1 downto 0);
        pulso_descida : out std_logic_vector(N_G-1 downto 0)
    );
end entity detector_borda;

architecture arch of detector_borda is
    signal entrada_atrasada : std_logic_vector(N_G-1 downto 0) := (others => '0');
begin
    process(clock, reset)
    begin
        if reset = '1' then
            entrada_atrasada <= (others => '0');

        elsif rising_edge(clock) then
            entrada_atrasada <= entrada;
        end if;
    end process;

    pulso_subida  <= entrada and not entrada_atrasada;
    pulso_descida <= not entrada and entrada_atrasada;
end architecture arch;
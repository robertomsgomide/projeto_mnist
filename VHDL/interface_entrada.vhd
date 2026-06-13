-------------------------------------------------------------------------------
-- Arquivo   : interface_entrada.vhd
-------------------------------------------------------------------------------
-- Descricao : adapta sinais logicos de controle para o dominio de clock do
--             projeto com entrada dinamica via UART. Gera habilitacao de
--             escrita, pulso de classificacao e pulso de limpeza.
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     18/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  versao inicial
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity interface_entrada is
    port (
        clock : in std_logic;

        escreve    : in std_logic;
        apaga      : in std_logic;
        classifica : in std_logic;

        escrita_habilitada : out std_logic;
        limpa_canvas_pulso : out std_logic;
        classifica_pulso   : out std_logic
    );
end entity interface_entrada;

architecture arch of interface_entrada is

    component sincronizador_sinais is
        generic (
            N_G : positive := 1
        );
        port (
            clock : in std_logic;
            reset : in std_logic;

            entrada_async : in  std_logic_vector(N_G-1 downto 0);
            saida_sync    : out std_logic_vector(N_G-1 downto 0)
        );
    end component;

    component detector_borda is
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
    end component;

    signal controles_async_s   : std_logic_vector(2 downto 0) := (others => '0');
    signal controles_sync_s    : std_logic_vector(2 downto 0) := (others => '0');
    signal controles_subida_s  : std_logic_vector(2 downto 0) := (others => '0');
    signal controles_descida_s : std_logic_vector(2 downto 0) := (others => '0');

begin

    controles_async_s(0) <= escreve;
    controles_async_s(1) <= apaga;
    controles_async_s(2) <= classifica;

    u_sinc_controles : sincronizador_sinais
        generic map (
            N_G => 3
        )
        port map (
            clock         => clock,
            reset         => '0',
            entrada_async => controles_async_s,
            saida_sync    => controles_sync_s
        );

    u_borda_controles : detector_borda
        generic map (
            N_G => 3
        )
        port map (
            clock         => clock,
            reset         => '0',
            entrada       => controles_sync_s,
            pulso_subida  => controles_subida_s,
            pulso_descida => controles_descida_s
        );

    escrita_habilitada <= controles_sync_s(0);
    limpa_canvas_pulso <= controles_subida_s(1);
    classifica_pulso   <= controles_subida_s(2);

end architecture arch;

-------------------------------------------------------------------------------
-- Arquivo   : contador_pixel.vhd
-------------------------------------------------------------------------------
-- Descricao : contador de pixels usado pelo classificador denso sequencial.
--             Percorre os indices 0..783 da imagem MNIST durante a inferencia.
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     18/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  versao inicial
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;

entity contador_pixel is
    port (
        clock : in std_logic;
        reset : in std_logic;

        limpa    : in std_logic;
        habilita : in std_logic;

        contagem : out pixel_addr_t;
        fim      : out std_logic
    );
end entity contador_pixel;

architecture arch of contador_pixel is
    signal cont : pixel_addr_t := (others => '0');
begin
    process(clock, reset)
    begin
        if reset = '1' then
            cont <= (others => '0');

        elsif rising_edge(clock) then
            if limpa = '1' then
                cont <= (others => '0');

            elsif habilita = '1' then
                if cont /= to_unsigned(IMG_BITS_C-1, cont'length) then
                    cont <= cont + 1;
                end if;
            end if;
        end if;
    end process;

    contagem <= cont;
    fim      <= '1' when cont = to_unsigned(IMG_BITS_C-1, cont'length) else '0';
end architecture arch;
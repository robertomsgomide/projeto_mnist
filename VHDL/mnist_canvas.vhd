-------------------------------------------------------------------------------
-- Arquivo   : mnist_canvas.vhd
-------------------------------------------------------------------------------
-- Descricao : responsavel por armazenar a imagem dinamica fornecida pela ESP32.
--             Funciona como o "quadro branco" interno do sistema. A escrita e
--             habilitada por escreve, a limpeza e comandada por apaga, e o
--             conteudo salvo e usado pelo fluxo de dados dos classificadores
--             quando classifica solicita uma classificacao.
--
--             Cada frame completo recebido pela UART substitui integralmente o
--             conteudo anterior do canvas. Pixels em '0' no frame recebido
--             apagam pixels anteriores.
-------------------------------------------------------------------------------
-- Revisoes  :
--     Data        Versao  Autor                                Descricao
--     18/05/2026  1.0     Roberto M S Gomide / Rodrigo Haruna  versao inicial
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mnist_tipos_pkg.all;

entity mnist_canvas is
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
end entity mnist_canvas;

architecture arch of mnist_canvas is

    signal imagem_reg_s : imagem_mnist_t := (others => '0');
    signal valida_reg_s : std_logic := '0';
    signal alterada_s   : std_logic := '0';

    constant ZERO_IMAGE_C : imagem_mnist_t := (others => '0');

begin

    process(clock, reset)
    begin
        if reset = '1' then
            imagem_reg_s <= ZERO_IMAGE_C;
            valida_reg_s <= '0';
            alterada_s   <= '0';

        elsif rising_edge(clock) then
            alterada_s <= '0';

            -------------------------------------------------------------------
            -- Limpeza tem prioridade sobre carregamento de frame.
            -------------------------------------------------------------------
            if limpa_canvas_pulso = '1' then
                imagem_reg_s <= ZERO_IMAGE_C;
                valida_reg_s <= '0';
                alterada_s   <= '1';

            -------------------------------------------------------------------
            -- Frame completo substitutivo.
            -------------------------------------------------------------------
            elsif escrita_habilitada = '1' and frame_recebido_valido = '1' then
                imagem_reg_s <= frame_recebido;
                alterada_s   <= '1';

                if frame_recebido = ZERO_IMAGE_C then
                    valida_reg_s <= '0';
                else
                    valida_reg_s <= '1';
                end if;
            end if;
        end if;
    end process;

    imagem_atual          <= imagem_reg_s;
    imagem_valida         <= valida_reg_s;
    imagem_alterada_pulso <= alterada_s;

end architecture arch;

# A GERAÇÃO QUE VALE de uma base baixada (#2858, F5), para os modelos das tabelas de cada base, num comando só: a
# geração é lida numa subconsulta do MESMO comando SQL. Serve à conferência de um comando (console, specs). A busca do
# agente faz vários comandos e por isso fixa a geração uma vez (`Bases::Provedor#da_base`). Quem inclui define `BASE`
# (a chave da base no `Estado`).
module Autonomia::FerramentasProntas::Bases::Vigente
  extend ActiveSupport::Concern

  class_methods do
    def vigente
      where("geracao = (SELECT geracao_ativa FROM autonomia_prontas_bases WHERE base = #{connection.quote(self::BASE)})")
    end
  end
end

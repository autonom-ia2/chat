# A GERAÇÃO QUE VALE de uma base baixada (#2858, F5), para os modelos das tabelas de cada base. A busca lê a geração
# numa subconsulta do MESMO comando SQL: o comando vê uma foto só do banco, então, durante a troca, ele acha a geração
# antiga inteira ou a nova inteira, nunca nenhuma. Quem inclui define `BASE` (a chave da base no `Estado`).
module Autonomia::FerramentasProntas::Bases::Vigente
  extend ActiveSupport::Concern

  class_methods do
    def vigente
      where("geracao = (SELECT geracao_ativa FROM autonomia_prontas_bases WHERE base = #{connection.quote(self::BASE)})")
    end
  end
end

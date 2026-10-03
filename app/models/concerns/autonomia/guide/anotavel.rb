# Liga todo model ao caderno do Guia (#855). Fora de uma ação do Guia, cada
# callback só confere uma variável da thread e volta.
#
# Fica em ApplicationRecord, antes dos callbacks de cada model: o `antes` de
# apagar é lido ANTES de `dependent: :destroy` apagar os filhos, e a anotação
# de apagado sai DEPOIS deles. É essa ordem que deixa o desfazer recriar o pai
# antes dos filhos.
#
# Sem `after_rollback` de propósito: callback transacional em TODO model faria
# cada gravação da plataforma ficar presa à transação até o commit. O caderno
# confere no fim da ação o que de fato ficou no banco (`Diario#persistir`).
module Autonomia::Guide::Anotavel
  extend ActiveSupport::Concern

  included do
    before_update { ::Autonomia::Guide::Diario.antes_de_alterar(self) if ::Autonomia::Guide::Diario.ativo? }
    after_update { ::Autonomia::Guide::Diario.depois_de_alterar(self) if ::Autonomia::Guide::Diario.ativo? }
    after_create { ::Autonomia::Guide::Diario.depois_de_criar(self) if ::Autonomia::Guide::Diario.ativo? }
    before_destroy { ::Autonomia::Guide::Diario.antes_de_apagar(self) if ::Autonomia::Guide::Diario.ativo? }
    after_destroy { ::Autonomia::Guide::Diario.depois_de_apagar(self) if ::Autonomia::Guide::Diario.ativo? }
  end
end

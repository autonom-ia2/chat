# Tipo de decisor que a busca procura (#677). Catálogo do Orth (lib/research/decisor-role-options.ts): só o
# Proprietário tem pesquisa pronta. Os outros existem para a tela mostrar "em breve"; o servidor não aceita nenhum deles,
# porque desabilitar na tela não impede quem chama a API direto.
module Autonomia::Prospecting::DecisionMakerType
  DEFAULT = 'owner'.freeze
  ALL = %w[owner ceo commercial financial marketing hr operations technology legal compliance risk].freeze
  AVAILABLE = %w[owner].freeze

  module_function

  # Valor para gravar em search.metadata['decision_maker_type']: o pedido, se tiver pesquisa pronta, ou o padrão.
  def normalize(value)
    AVAILABLE.include?(value.to_s) ? value.to_s : DEFAULT
  end
end

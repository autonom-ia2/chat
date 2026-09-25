# Lista fechada de campos de pessoa física que a pesquisa pode gravar (#679). Tudo que vai para o banco sobre uma
# pessoa (sócio no quadro, dono escolhido) passa por storable!. Campo fora da lista não é descartado em silêncio aqui:
# é erro de montagem, e quem grava trata como falha e não grava nada. O descarte dos campos que as fontes mandam (CPF
# mascarado, faixa etária, representante legal) acontece antes, no parser, que nem lê esses campos para o Partner.
module Autonomia::Prospecting::Research::PersonFields
  ALLOWED = %w[name qualification entered_on].freeze

  # A mensagem cita só o nome dos campos, nunca o valor.
  class Violation < StandardError; end

  module_function

  def storable!(entry)
    entry = entry.to_h.transform_keys(&:to_s)
    extra = entry.keys - ALLOWED
    raise Violation, "campo de pessoa física fora da lista fechada: #{extra.join(', ')}" if extra.any?

    entry
  end
end

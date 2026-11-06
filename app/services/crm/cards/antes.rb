# O valor de antes dos campos que uma edição do card mudou (G27, #2661), para a atividade 'update' levar ao lado do que
# foi gravado. O gatilho "card atualizado" da Automação lê dele o que mudou e de quanto ("o valor passou de R$ 50 mil").
# O histórico desenha a linha como antes (só o que foi gravado); a API devolve o `antes` a quem vê o card, e o
# `antes.value_cents` segue a mesma regra do valor de venda (#2075).
#
# Lê o `saved_changes` logo depois do `update!`, só dos campos do pedido que o gatilho lê (LIDOS): o valor e os campos
# personalizados. Título, descrição e metadata não vão: o histórico não guarda cópia deles. Nos personalizados, só as
# chaves que de fato mudaram (o upsert manda o hash inteiro já juntado). Nada mudou, {}.
#
#   Crm::Cards::Antes.de(card, %w[value_cents custom_attributes])
#   -> { 'value_cents' => 1_000_000, 'custom_attributes' => { 'documentos' => nil } }
module Crm::Cards::Antes
  PERSONALIZADOS = 'custom_attributes'.freeze
  LIDOS = ['value_cents', PERSONALIZADOS].freeze

  module_function

  def de(card, campos)
    mudancas = card.saved_changes
    (campos.map(&:to_s) & LIDOS).each_with_object({}) do |campo, antes|
      next unless mudancas.key?(campo)

      velho, novo = mudancas[campo]
      antes[campo] = campo == PERSONALIZADOS ? chaves_mudadas(velho.to_h, novo.to_h) : velho
    end
  end

  # Num payload de atividade: o mesmo payload com `antes`, quando a edição mudou algo.
  def no_payload(payload, card)
    antes = de(card, payload.keys)
    antes.present? ? payload.merge(antes: antes) : payload
  end

  def chaves_mudadas(velho, novo)
    (velho.keys | novo.keys).reject { |chave| velho[chave] == novo[chave] }.index_with { |chave| velho[chave] }
  end
end

# O valor do negócio achado na conversa pela avaliação do card (Crm::Ai::Evaluator), gravado direto em value_cents
# (decisão de produto: "autopreenche sempre"). A ÚNICA guarda é a pessoa: depois que alguém edita o valor à mão
# (value_source = 'human'), nenhuma avaliação seguinte desfaz a correção.
# #1498: funil de Atender não tem valor de venda; a IA não preenche (a Cobrança guarda o valor que a pessoa digita).
module Crm::Ai::ValorAchado
  module_function

  def aplicar!(card, ai_metadata, value, attributes)
    valor = valor_novo(card, ai_metadata, value)
    return if valor.nil?

    attributes.merge!(valor)
    ai_metadata['value_source'] = 'ai'
    ai_metadata['value_filled_at'] = Time.current.iso8601
  end

  # { value_cents:, currency: } quando há valor novo para gravar; nil quando não há.
  def valor_novo(card, ai_metadata, value)
    return unless card.pipeline&.counts_as_sale? && ai_metadata['value_source'] != 'human'

    valor = lido(value)
    valor unless valor.nil? || (valor[:value_cents] == card.value_cents && valor[:currency] == card.currency)
  end

  # O valor como o modelo devolveu, completo (centavos e moeda), ou nil.
  def lido(value)
    value = value.with_indifferent_access if value.respond_to?(:with_indifferent_access)
    return if value.blank? || value[:amount_cents].blank? || value[:currency].blank?

    { value_cents: value[:amount_cents].to_i, currency: value[:currency].to_s.upcase }
  end
end

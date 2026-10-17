# D6 (decisão do Rodrigo, 16/10/2026): o pedido ganho, perdido, resolvido ou cancelado entra na memória do CLIENTE como
# fato (resultado, item, data), por 360 dias, sem modelo. Só o resultado em categoria, o item natural do pedido (a placa,
# o produto; sem ele, o nome do funil) e a data. O motivo da perda e o título interno do card nunca entram. Pedido
# encerrado não reabre sozinho: o card reaberto tira o fato.
module Crm::Memoria::Fechamento
  RESULTADOS = { 'won' => 'ganho', 'lost' => 'perdido', 'resolved' => 'resolvido', 'cancelled' => 'cancelado' }.freeze
  VALIDADE = 360.days

  module_function

  def registrar!(card)
    return if card.contact_id.nil? || !Crm::Memoria.ligada?(card.account)
    return reaberto!(card) if card.open?

    resultado = RESULTADOS[card.status]
    return if resultado.nil?

    gravar!(card, resultado, card.closed_at || card.updated_at)
  end

  def gravar!(card, resultado, data)
    item = item_do(card)
    fuso = Crm::Timezone::Resolver.new(account: card.account).name_or_default
    Crm::Memoria::Gravador.gravar!(
      account_id: card.account_id, contact_id: card.contact_id, escopo: 'contato', tipo: 'pedido_encerrado',
      chave: Crm::Memoria::Catalogo::PEDIDO_ENCERRADO, item_ref: "card:#{card.id}",
      valor: "#{resultado} · #{item} · #{data.in_time_zone(fuso).strftime('%d/%m/%Y')}",
      valor_json: { 'resultado' => resultado, 'item' => item, 'data' => data.iso8601, 'pipeline_id' => card.pipeline_id },
      fonte: 'sistema', status: 'confirmado', valido_desde: data, vence_em: data + VALIDADE,
      gerado_por: 'codigo:fechamento@1', idempotency_key: "fechamento:#{card.id}:#{card.status}:#{data.to_i}"
    )
  end

  def reaberto!(card)
    Crm::MemoriaFato.vigentes.where(account_id: card.account_id, contact_id: card.contact_id, escopo: 'contato',
                                    tipo: 'pedido_encerrado', item_ref: "card:#{card.id}")
                    .update_all(expirado_em: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  # O item natural do pedido (a chave marcada no catálogo), senão o nome do funil.
  def item_do(card)
    naturais = Crm::MemoriaChave.where(account_id: card.account_id, attribute_model: 'card_attribute', item_natural: true).pluck(:chave)
    fato = Crm::MemoriaFato.vigentes.where(account_id: card.account_id, escopo: 'card', card_id: card.id, chave: naturais).first
    Crm::Memoria::Normal.linha(fato&.valor.presence || card.pipeline&.name).first(80)
  end
end

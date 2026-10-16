# `waha_order` (chat#1709, rodada 2): pedido do catálogo (orderMessage), { order_id, title, text, item_count,
# total_amount, currency, status, seller_jid }, que na main é a nota de "não suportada". Com a flag vira mensagem do
# cliente com `content_attributes.order` no formato da Cloud { catalog_id: nil, text, items: [] }, com os extras
# combinados com o Frontend geral (#1702): `order_id` (sempre, em texto), `item_count`, `total_amount` (texto decimal
# com ponto e 2 casas, ex. "150.00", a partir do número que o conector tira do totalAmount1000 do proto), `currency` e
# `title`. O proto não traz os itens: `items` vem vazio. O texto do pedido (ou o título) vira o `content`. Só a nota
# do CLIENTE, pelo `from_me` false explícito que o conector (c2y-rich-3b) manda: a nota privada do conector sai
# OUTGOING também quando é do cliente, então a direção não serve.
# `from_me` true ou ausente: fica como a main.
module Waha::RichNative::Inbound::Order
  KEY = 'order'.freeze

  module_function

  def apply(message, data)
    return unless order?(data) && message.conversation&.contact

    message.message_type = :incoming
    message.private = false
    message.sender = message.conversation.contact
    message.content = data['text'].presence || data['title'].presence || message.content
    message.content_attributes = message.content_attributes.to_h.merge(KEY => order_for(data))
  end

  def order?(data)
    data.is_a?(Hash) && data['from_me'] == false && data['order_id'].present?
  end

  def order_for(data)
    { 'catalog_id' => nil, 'text' => data['text'], 'items' => [], 'order_id' => data['order_id'].to_s,
      'item_count' => data['item_count'], 'total_amount' => amount(data['total_amount']), 'currency' => data['currency'],
      'title' => data['title'] }
  end

  # Número (ou texto numérico) em texto decimal com ponto e 2 casas, sem perder precisão; nil quando não é número.
  def amount(value)
    decimal = BigDecimal(value.to_s, exception: false) if value.is_a?(Numeric) || value.is_a?(String)
    return if decimal.nil? || !decimal.finite?

    units, cents = decimal.round(2).abs.to_s('F').split('.')
    "#{'-' if decimal.negative?}#{units}.#{cents.to_s.ljust(2, '0')}"
  end
end

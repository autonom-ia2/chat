# `waha_order` (chat#1709, rodada 2): pedido do catálogo (orderMessage), { order_id, title, text, item_count,
# total_amount, currency, status, seller_jid }, que na main é a nota de "não suportada". Com a flag vira mensagem do
# cliente com `content_attributes.order` no formato da Cloud { catalog_id: nil, text, product_items: [], order_id,
# item_count, total_amount, currency, title } (o proto não traz os itens; formato a combinar com o Frontend geral). O
# texto do pedido (ou o título) vira o `content`. Só a nota do CLIENTE, pelo `from_me` false explícito que o conector
# (c2y-rich-3b) manda: a nota privada do conector sai OUTGOING também quando é do cliente, então a direção não serve.
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
    { 'catalog_id' => nil, 'text' => data['text'], 'product_items' => [], 'order_id' => data['order_id'].to_s,
      'item_count' => data['item_count'], 'total_amount' => data['total_amount'], 'currency' => data['currency'],
      'title' => data['title'] }
  end
end

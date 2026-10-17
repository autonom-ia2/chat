# Pedido do catálogo que o cliente manda pelo carrinho do WhatsApp (#1702), `type: "order"`:
# https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/reference/messages/order.md
#
#   content_attributes['order'] = { 'catalog_id' => '…', 'text' => '…',
#                                   'items' => [{ 'product_retailer_id', 'quantity', 'item_price', 'currency' }] }
#
# O `content` vira um resumo legível ("Pedido do catálogo: 3 itens · total BRL 150,00") para quem não tem a pele do
# pedido: lista de conversas, notificação, robô e exportação.
class ConversaCanal::PedidoRecebido
  CAMPOS_DO_ITEM = %w[product_retailer_id quantity item_price currency].freeze

  def initialize(order, locale: nil)
    @order = order.respond_to?(:to_h) ? order.to_h.with_indifferent_access : {}
    @locale = locale.presence || I18n.default_locale
  end

  def atributos
    { 'catalog_id' => @order[:catalog_id], 'text' => @order[:text].presence, 'items' => itens }.compact
  end

  def texto
    resumo = I18n.t('conversa_canal.pedido.resumo', locale: @locale, itens: quantidade_de_itens)
    resumo += I18n.t('conversa_canal.pedido.total', locale: @locale, total: total) if total
    [resumo, @order[:text].presence].compact.join("\n")
  end

  private

  def itens
    Array(@order[:product_items]).select { |item| item.respond_to?(:to_h) }.map { |item| item.to_h.stringify_keys.slice(*CAMPOS_DO_ITEM) }
  end

  def quantidade_de_itens
    I18n.t('conversa_canal.pedido.itens', locale: @locale, count: itens.sum { |item| item['quantity'].to_i })
  end

  # Só com uma moeda e todos os preços numéricos; senão o resumo sai sem total.
  def total
    return @total if defined?(@total)

    @total = total_formatado
  end

  def total_formatado
    moeda = moeda_unica
    precos = itens.map { |item| BigDecimal(item['item_price'].to_s, exception: false) }
    return if moeda.nil? || precos.any?(&:nil?)

    soma = itens.zip(precos).sum { |item, preco| preco * item['quantity'].to_i }
    ActiveSupport::NumberHelper.number_to_currency(
      soma, unit: moeda, format: '%u %n',
            separator: I18n.t('conversa_canal.pedido.separador_decimal', locale: @locale),
            delimiter: I18n.t('conversa_canal.pedido.separador_de_milhar', locale: @locale)
    )
  end

  def moeda_unica
    moedas = itens.pluck('currency').uniq
    moedas.first if moedas.size == 1 && moedas.first.present?
  end
end

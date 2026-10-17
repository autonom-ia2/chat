# Pedido do catálogo que o cliente manda pelo carrinho do WhatsApp (#1702), `type: "order"`:
# https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/reference/messages/order.md
#
#   content_attributes['order'] = { 'catalog_id' => '…', 'text' => '…',
#                                   'items' => [{ 'product_retailer_id', 'quantity', 'item_price', 'currency' }] }
#
# O `content` vira um resumo legível ("Pedido do catálogo: 3 itens · total BRL 150,00", uma linha por item com o código
# e a quantidade, e o texto do cliente) para quem não tem a pele do pedido: lista de conversas, notificação, robô e
# exportação. O item vai pelo código do catálogo: a IA não precisa adivinhar o produto (revisão dos Agentes IA, 17/10).
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
    [resumo, *linhas_dos_itens, @order[:text].presence].compact.join("\n")
  end

  private

  def itens
    # Lista de objetos; qualquer outra forma (objeto solto, texto) fica sem itens, e o pedido entra só com o resumo.
    lista = @order[:product_items]
    return [] unless lista.is_a?(Array)

    lista.select { |item| item.is_a?(Hash) }.map { |item| item.to_h.stringify_keys.slice(*CAMPOS_DO_ITEM) }
  end

  def quantidade_de_itens
    I18n.t('conversa_canal.pedido.itens', locale: @locale, count: itens.sum { |item| quantidade(item) })
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

    soma = itens.zip(precos).sum { |item, preco| preco * quantidade(item) }
    ActiveSupport::NumberHelper.number_to_currency(
      soma, unit: moeda, format: '%u %n',
            separator: I18n.t('conversa_canal.pedido.separador_decimal', locale: @locale),
            delimiter: I18n.t('conversa_canal.pedido.separador_de_milhar', locale: @locale)
    )
  end

  def linhas_dos_itens
    itens.filter_map do |item|
      codigo = item['product_retailer_id'].to_s.strip.first(80)
      I18n.t('conversa_canal.pedido.item', locale: @locale, codigo: codigo, quantidade: quantidade(item)) if codigo.present?
    end
  end

  # Quantidade que não é número nem texto (lista, objeto) conta zero.
  def quantidade(item)
    valor = item['quantity']
    valor.is_a?(Numeric) || valor.is_a?(String) ? valor.to_i : 0
  end

  def moeda_unica
    moedas = itens.pluck('currency').uniq
    moedas.first if moedas.size == 1 && moedas.first.present?
  end
end

# Modelo de produto e carrossel mandados pela CONVERSA (#1716, épico #1320). A tela da conversa escolhe os produtos e
# monta os cartões; aqui o pedido é completado com os MESMOS construtores da campanha, sem caminho novo de envio:
#   produtos  — `ProductParams.normalize!` confere os códigos e a quantidade; `DispatchProducts` relê o catálogo da WABA
#               da caixa (produto esgotado ou fora do catálogo não sai) e devolve o catálogo, que entra em
#               `products.catalog_id` (nunca vem da tela);
#   carrossel — `SendParams.with_carousel` confere cada cartão (arquivo desta conta, do tipo e do tamanho que a Meta
#               aceita; texto do cartão preenchido) e `CardMedia.for_dispatch` + `SendParams.apply_extras` trocam o
#               arquivo escolhido pelo link assinado que vai à Meta, como no disparo da campanha.
# Quem chama: `Whatsapp::Templates::ConversationSendGuard`, depois de a regra única (`SendableFormat`) dizer que o pedido
# está completo. A falha vira o motivo na conversa, SEM chamar a Meta para enviar.
module Whatsapp::Templates::ConversationSend
  Result = Data.define(:processed, :error, :details) do
    def ok?
      error.nil?
    end
  end

  PRODUCTS_FLAG = 'whatsapp_campaign_products'.freeze
  # Motivo do `DispatchProducts` -> chave do texto (whatsapp_templates.errors.*).
  PRODUCT_ERRORS = { 'template_catalog_missing' => 'conversation_catalog_missing',
                     'template_product_unavailable' => 'conversation_product_unavailable' }.freeze

  module_function

  # O `processed_params` pronto para o envio (nil quando o modelo não é de produto nem carrossel: segue como antes).
  def prepare(template:, processed:, inbox:)
    processed = processed.is_a?(Hash) ? processed.deep_dup : {}
    return products(template, processed, inbox) if Whatsapp::Templates::ProductParams.kind(template)
    return carousel(template, processed, inbox) if Whatsapp::Templates::SendParams.cards_of(template).any?

    ok(nil)
  end

  def products(template, processed, inbox)
    return failure('conversation_products_disabled') unless inbox.account.feature_enabled?(PRODUCTS_FLAG)

    processed = Whatsapp::Templates::ProductParams.normalize!(processed, template)
    check = Whatsapp::Templates::DispatchProducts.new(inbox: inbox, template: template, processed: processed).call
    return failure(PRODUCT_ERRORS.fetch(check.reason_code, 'conversation_products'), check.details) unless check.ok?

    ok(processed.merge('products' => processed['products'].merge('catalog_id' => check.catalog_id)))
  rescue Whatsapp::Templates::HeaderMedia::Invalid
    failure('conversation_products')
  rescue Whatsapp::Templates::MetaClient::Unsupported
    failure('conversation_catalog_missing')
  rescue Whatsapp::Templates::MetaClient::Unreachable, Whatsapp::Templates::MetaClient::MetaError => e
    Rails.logger.warn("[whatsapp_templates][conversation_send] catalog_unreadable inbox_id=#{inbox.id} error=#{e.class}")
    failure('conversation_catalog_unreachable')
  end

  def carousel(template, processed, inbox)
    processed = Whatsapp::Templates::SendParams.with_carousel(processed, template, inbox)
    cards = Whatsapp::Templates::CardMedia.for_dispatch(processed, template, inbox)
    return failure('conversation_carousel_media') if cards.nil?

    ok(Whatsapp::Templates::SendParams.apply_extras(processed, { cards: cards }))
  rescue Whatsapp::Templates::HeaderMedia::Invalid
    failure('conversation_carousel')
  end

  def ok(processed)
    Result.new(processed: processed, error: nil, details: {})
  end

  def failure(error, details = {})
    Result.new(processed: nil, error: error, details: details.to_h)
  end
end

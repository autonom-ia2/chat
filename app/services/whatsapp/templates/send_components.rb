# Os formatos novos no envio de um modelo (#1334, épico #1320). Prependido em `Whatsapp::TemplateProcessorService` (do
# Chatwoot) pelo `config/initializers/whatsapp_templates.rb`: o arquivo do Chatwoot fica intacto.
#
# Só acrescenta componentes quando `processed_params` traz as chaves novas. Sem elas (conversa, diálogo antigo de
# campanha), o payload é exatamente o de antes:
#   limited_time_offer: { expiration_time_ms: <Unix em milissegundos> }   oferta por tempo limitado com validade
#   carousel: { cards: [{ header: { media_url, media_type }, body: { '1' => … }, buttons: [{ type: 'quick_reply',
#              payload: … } | { type: 'url', parameter: … } | nil] }] }   um item por cartão do modelo, na ordem dele
#   buttons[i]: { type: 'flow', flow_token: … }                            botão de formulário (Flow)
#   buttons[i]: { type: 'catalog', thumbnail_product_retailer_id?: … }     botão de catálogo
#   buttons[i]: { type: 'quick_reply', payload: … }                        resposta rápida com payload estável (#1473): a Meta
#                                                                          devolve o payload, não o texto do botão
#   products: { retailer_ids: [...], catalog_id: … }                       produtos do catálogo (#1418): topo do produto, botão
#                                                                          MPM ou cartões (Whatsapp::Templates::ProductParams)
# O cupom (botão COPY_CODE) já era enviado pelo Chatwoot (`{ type: 'copy_code', parameter: … }`).
#
# Formato de cada componente conforme a documentação oficial da Meta, lida em 13/10/2026:
#   developers.facebook.com/documentation/business-messaging/whatsapp/templates/marketing-templates/
#     limited-time-offer-templates (limited_time_offer.expiration_time_ms) e media-card-carousel-templates (cards[])
#   developers.facebook.com/documentation/business-messaging/whatsapp/catalogs/catalog-template-messages
#     (sem `parameters`, a Meta usa o primeiro item do catálogo)
#   developers.facebook.com/docs/whatsapp/flows/guides/sendingaflow (action.flow_token)
module Whatsapp::Templates::SendComponents
  private

  def process_enhanced_template_params(template, processed_params = nil)
    params = (processed_params || template_params['processed_params']).to_h
    components = super
    products = Whatsapp::Templates::ProductParams.components(template, params)
    extras = offer_components(template, params) + carousel_components(template, params) + products[:after_body]
    buttons = extra_button_components(template, params) + products[:buttons]
    return components if extras.empty? && buttons.empty? && products[:header].empty?

    @template_params = products[:header] + after_body(components, extras) + buttons
  end

  # Oferta e carrossel vão logo depois do corpo, como nos exemplos da Meta; os botões ficam no fim.
  def after_body(components, extras)
    position = components.index { |component| component[:type] == 'button' } || components.size
    components.take(position) + extras + components.drop(position)
  end

  # Cada parte só vai quando o modelo tem o componente ou o botão na mesma posição: chave sobrando não chega à Meta.
  def offer_components(template, params)
    expiration = params['limited_time_offer'].is_a?(Hash) ? params['limited_time_offer']['expiration_time_ms'] : nil
    return [] if expiration.blank? || !template_part?(template, 'LIMITED_TIME_OFFER')

    [{ type: 'limited_time_offer',
       parameters: [{ type: 'limited_time_offer', limited_time_offer: { expiration_time_ms: expiration.to_i } }] }]
  end

  def carousel_components(template, params)
    cards = params['carousel'].is_a?(Hash) ? Array(params['carousel']['cards']) : []
    return [] if cards.empty? || !template_part?(template, 'CAROUSEL')

    [{ type: 'carousel', cards: cards.each_with_index.map { |card, index| card_payload(template, card.is_a?(Hash) ? card : {}, index) } }]
  end

  # Topo com o arquivo subido no disparo (`media_id`, #2367): vai pelo id; sem id, o Chatwoot manda o link.
  def build_media_header_params(header_data)
    media = Whatsapp::Templates::MetaMediaId.parameter(header_data)
    media ? [media] : super
  end

  def card_payload(template, card, index)
    header = card['header'].is_a?(Hash) ? card['header'] : {}
    media = Whatsapp::Templates::MetaMediaId.parameter(header) ||
            parameter_builder.build_media_parameter(header['media_url'], header['media_type'].to_s, header['media_name'])
    components = []
    components << { type: 'header', parameters: [media] } if media
    body = card_body(template, card['body'])
    components << body if body
    { card_index: index, components: components + card_buttons(card['buttons']) }
  end

  def card_body(template, values)
    values = (values.is_a?(Hash) ? values : {}).reject { |_key, value| value.blank? }
    return if values.empty?

    values = values.sort_by { |key, _value| key.to_i } unless template['parameter_format'] == 'NAMED'
    { type: 'body', parameters: values.map { |key, value| build_text_parameter(key, value, template) } }
  end

  def card_buttons(buttons)
    Array(buttons).each_with_index.filter_map do |button, index|
      next unless button.is_a?(Hash)

      case button['type']
      when 'quick_reply' then quick_reply_button(button, index)
      when 'url' then url_button(button, index)
      end
    end
  end

  def quick_reply_button(button, index)
    return if button['payload'].blank?

    { type: 'button', sub_type: 'quick_reply', index: index, parameters: [{ type: 'payload', payload: button['payload'].to_s }] }
  end

  def url_button(button, index)
    return if button['parameter'].blank?

    { type: 'button', sub_type: 'url', index: index, parameters: [parameter_builder.build_button_parameter(button)] }
  end

  def extra_button_components(template, params)
    kinds = template_button_types(template)
    Array(params['buttons']).each_with_index.filter_map do |button, index|
      next unless button.is_a?(Hash)

      case [button['type'], kinds[index]]
      when %w[flow FLOW] then flow_button(button, index)
      when %w[catalog CATALOG] then catalog_button(button, index)
      # #1473: com `parameter`, o Chatwoot já monta o botão; aqui só o payload estável.
      when %w[quick_reply QUICK_REPLY] then quick_reply_button(button, index) if button['parameter'].blank?
      end
    end
  end

  def template_part?(template, type)
    Array(template['components']).any? { |component| component.is_a?(Hash) && component['type'].to_s.casecmp?(type) }
  end

  def template_button_types(template)
    buttons = Array(template['components']).find { |component| component.is_a?(Hash) && component['type'].to_s.casecmp?('BUTTONS') }
    Array(buttons&.dig('buttons')).map { |button| button.is_a?(Hash) ? button['type'].to_s.upcase : '' }
  end

  def flow_button(button, index)
    return if button['flow_token'].blank?

    { type: 'button', sub_type: 'flow', index: index,
      parameters: [{ type: 'action', action: { flow_token: button['flow_token'].to_s } }] }
  end

  def catalog_button(button, index)
    component = { type: 'button', sub_type: 'catalog', index: index }
    thumbnail = button['thumbnail_product_retailer_id'].presence
    return component unless thumbnail

    component.merge(parameters: [{ type: 'action', action: { thumbnail_product_retailer_id: thumbnail.to_s } }])
  end
end

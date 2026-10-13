# O que a campanha do WhatsApp oficial guarda e acrescenta para os formatos novos (#1334, épico #1320). O envio em si é
# montado por `Whatsapp::Templates::SendComponents`; a regra de "dá para enviar" é a `SendableFormat`.
#
# Na criação (`CampaignJourney::WhatsappCampaignCreator`), `normalize!` confere e completa o `processed_params`:
#   cupom (COPY_CODE)  — buttons[i].parameter de 1 a 15 caracteres (o envio do Chatwoot recusa mais de 15);
#   oferta             — com has_expiration, limited_time_offer.expiration_time_ms inteiro e à frente (Unix, em ms);
#   carrossel          — um item por cartão do modelo; cada topo com link http(s) ou, sem link, o arquivo do cartão
#                        guardado no perfil do modelo (marca `media_stored`, o link é gerado no disparo, porque expira);
#                        botão de site com final variável precisa do valor;
#   catálogo (CATALOG) — o botão é marcado sozinho; a Meta mostra o primeiro item do catálogo.
# Botão sem nada a enviar ocupa a posição dele como { 'type' => 'static' }: o conversor do Chatwoot só aceita a lista
# de botões sem buracos, e o envio pula o estático.
# No disparo (`CampaignPauses::WhatsappDispatchGate`), `dispatch_extras` gera uma vez por disparo o que vai em todo
# envio: o link de cada cartão guardado e o flow_token da campanha no botão de formulário.
#
# Fonte oficial (lida em 13/10/2026): developers.facebook.com/documentation/business-messaging/whatsapp/templates/
# marketing-templates/{coupon-templates,limited-time-offer-templates,media-card-carousel-templates},
# .../catalogs/catalog-template-messages e developers.facebook.com/docs/whatsapp/flows/guides/sendingaflow.
module Whatsapp::Templates::SendParams
  Invalid = Whatsapp::Templates::HeaderMedia::Invalid
  CODE_MAX = 15
  CARD_FORMATS = %w[IMAGE VIDEO].freeze
  FLOW_TOKEN_PREFIX = 'chat2you_campaign_'.freeze
  STATIC_BUTTON = CampaignJourney::TemplateVariableKeys::STATIC_BUTTON

  module_function

  def normalize!(processed, template:, inbox:, now: Time.current)
    processed = processed.to_h.deep_dup
    check_coupons!(processed, template)
    check_offer!(processed, template, now)
    processed = with_carousel(processed, template, inbox)
    with_catalog(processed, template)
  end

  def valid_code?(code)
    code.to_s.strip.length.between?(1, CODE_MAX)
  end

  def check_coupons!(processed, template)
    template_buttons(template).each_with_index do |button, index|
      next unless button['type'].to_s.casecmp?('COPY_CODE')
      raise Invalid, 'coupon_code_invalid' unless valid_code?(as_hash(recorded_buttons(processed)[index])['parameter'])
    end
  end

  # Sem a contagem no modelo, a Meta pede para não mandar a validade.
  def check_offer!(processed, template, now)
    return processed.delete('limited_time_offer') unless offer_with_expiration?(template)

    expiration = Integer(as_hash(processed['limited_time_offer'])['expiration_time_ms'].to_s, exception: false)
    raise Invalid, 'offer_expiration_required' unless expiration
    raise Invalid, 'offer_expiration_past' unless expiration > (now.to_f * 1000).to_i

    processed['limited_time_offer'] = { 'expiration_time_ms' => expiration }
  end

  def offer_with_expiration?(template)
    component(template, 'LIMITED_TIME_OFFER')&.dig('limited_time_offer', 'has_expiration') == true
  end

  def with_carousel(processed, template, inbox)
    template_cards = cards_of(template)
    return processed.except('carousel') if template_cards.empty?

    cards = Array(as_hash(processed['carousel'])['cards'])
    raise Invalid, 'carousel_cards_mismatch' unless cards.size == template_cards.size

    profile = Whatsapp::Templates::HeaderMedia.profile(inbox, template)
    normalized = cards.each_with_index.map { |card, index| checked_card(as_hash(card), template_cards[index], profile, index) }
    processed.merge('carousel' => { 'cards' => normalized })
  end

  def checked_card(card, template_card, profile, index)
    check_card_buttons!(card, template_card)
    card.merge('header' => card_header(card, template_card, profile, index))
  end

  def card_header(card, template_card, profile, index)
    type = card_format(template_card)
    raise Invalid, 'carousel_media_invalid' unless type

    url = as_hash(card['header'])['media_url'].to_s.strip
    return { 'media_url' => card_url!(url), 'media_type' => type } if url.present?
    raise Invalid, 'carousel_media_required' unless profile&.card_file(index)

    { 'media_stored' => true, 'media_type' => type }
  end

  # Botão de site do cartão com final variável: a Meta pede o valor no envio.
  def check_card_buttons!(card, template_card)
    sent = Array(card['buttons'])
    template_buttons(template_card).each_with_index do |button, index|
      next unless button['type'].to_s.casecmp?('URL') && CampaignJourney::TemplatePlaceholders.keys(button['url']).any?
      raise Invalid, 'carousel_button_required' if as_hash(sent[index])['parameter'].to_s.strip.empty?
    end
  end

  def card_url!(url)
    Whatsapp::Templates::HeaderMedia.check_url!(url)
    url
  rescue Invalid
    raise Invalid, 'carousel_media_invalid'
  end

  def with_catalog(processed, template)
    kinds = template_buttons(template)
    return processed if kinds.empty? || !(processed.key?('buttons') || kinds.any? { |button| catalog?(button) })

    sent = recorded_buttons(processed)
    processed.merge('buttons' => kinds.each_with_index.map { |button, index| button_at(button, sent[index]) })
  end

  def button_at(button, sent)
    return sent if sent.is_a?(Hash)

    catalog?(button) ? { 'type' => 'catalog' } : STATIC_BUTTON.dup
  end

  # { flow: { índice => token }, cards: { índice => { 'media_url', 'media_name' } } }; {} sem nada a acrescentar;
  # nil quando o arquivo de um cartão sumiu do perfil.
  # Formato antigo (lista de valores) não tem onde levar extras: segue como o Chatwoot envia.
  def dispatch_extras(processed, template:, inbox:, campaign:)
    return {} unless processed.is_a?(Hash)

    cards = stored_card_media(processed, template, inbox)
    return if cards.nil?

    flow = template_buttons(template).each_with_index.filter_map do |button, index|
      [index, "#{FLOW_TOKEN_PREFIX}#{campaign.id}"] if button['type'].to_s.casecmp?('FLOW')
    end
    extras = { flow: flow.to_h, cards: cards }
    extras.values.any?(&:present?) ? extras : {}
  end

  def stored_card_media(processed, template, inbox)
    cards = Array(as_hash(processed['carousel'])['cards'])
    stored = cards.each_index.select { |index| as_hash(as_hash(cards[index])['header'])['media_stored'] == true }
    return {} if stored.empty?

    profile = Whatsapp::Templates::HeaderMedia.profile(inbox, template)
    files = stored.index_with { |index| profile&.card_file(index) }
    return if files.values.any?(&:nil?)

    files.transform_values { |file| Whatsapp::Templates::HeaderMedia.signed_media(file) }
  end

  # O processed_params de um envio com os extras do disparo (o que a campanha guardou não muda).
  def apply_extras(processed, extras)
    processed = as_hash(processed).deep_dup
    processed = with_flow_tokens(processed, extras[:flow]) if extras[:flow].present?
    extras[:cards].to_h.each do |index, media|
      card = processed['carousel']['cards'][index]
      card['header'] = as_hash(card['header']).except('media_stored').merge(media)
    end
    processed
  end

  def with_flow_tokens(processed, flow)
    buttons = recorded_buttons(processed)
    size = [buttons.size, flow.keys.max + 1].max
    filled = Array.new(size) do |index|
      next buttons[index] if buttons[index].is_a?(Hash) && buttons[index]['type'] != STATIC_BUTTON['type']

      flow.key?(index) ? { 'type' => 'flow', 'flow_token' => flow[index] } : STATIC_BUTTON.dup
    end
    processed.merge('buttons' => filled)
  end

  def catalog?(button)
    button['type'].to_s.casecmp?('CATALOG')
  end

  def card_format(template_card)
    header = component(template_card, 'HEADER')
    format = header&.dig('format').to_s.upcase
    format.downcase if CARD_FORMATS.include?(format)
  end

  def cards_of(template)
    Whatsapp::Templates::SendableFormat.hashes(component(template, 'CAROUSEL')&.dig('cards'))
  end

  # Keeps the positions of the template (an entry that is not an object becomes {}): button indexes are positional.
  def template_buttons(template)
    Array(component(template, 'BUTTONS')&.dig('buttons')).map { |button| as_hash(button) }
  end

  def recorded_buttons(processed)
    processed['buttons'].is_a?(Array) ? processed['buttons'] : []
  end

  def component(template, type)
    Whatsapp::Templates::SendableFormat.hashes(as_hash(template)['components']).find { |item| item['type'].to_s.casecmp?(type) }
  end

  def as_hash(value)
    value.is_a?(Hash) ? value : {}
  end
end

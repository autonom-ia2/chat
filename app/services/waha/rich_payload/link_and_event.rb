# Os envios nativos da rodada 2 do chat#1709 (botão de link como cartão de prévia e convite de evento), separados do
# Waha::RichPayload, que os inclui. Leem `@rich` e `@body` dele.
module Waha::RichPayload::LinkAndEvent
  # Imagem do cartão de prévia do link (link_button): https, até este tamanho (o mesmo teto do endereço do botão).
  IMAGE_URL_MAX = 2000
  PREVIEW_IMAGE_MIMETYPE = 'image/jpeg'.freeze

  private

  # ---- link_button → cartão de prévia do link (rodada 2) ----
  # { text: "<corpo>\n\n<url>", preview: { url, title, description, image: { url, mimetype } } }. Só com `image_url`
  # (https, até IMAGE_URL_MAX): o motor GOWS 2026.9.2 dá erro 500 sem a imagem. Sem ela, nil: sai o texto de hoje, e o
  # WhatsApp mostra a prévia automática do site. O texto contém a url, como o motor exige.
  def link_preview
    return @link_preview if defined?(@link_preview)

    @link_preview = build_link_preview
  end

  def build_link_preview
    url = link_button_url
    image = preview_image_url
    return if url.nil? || image.nil? || @body.strip.blank?

    label = @rich[:label].to_s
    { text: "#{@body}\n\n#{url}",
      preview: { url: url, title: @rich[:header].presence || label, description: @rich[:footer].presence || label,
                 image: { url: image, mimetype: PREVIEW_IMAGE_MIMETYPE } } }
  end

  # O endereço do botão, como o tipo o valida (RichMessages::Types::LinkButton). nil quando o botão é inválido.
  def link_button_url
    button = RichMessages::Types::LinkButton.new(@rich.to_hash.stringify_keys)
    @rich[:url] if button.error_for(@body).nil?
  end

  def preview_image_url
    value = @rich[:image_url]
    return unless value.is_a?(String) && value.length <= IMAGE_URL_MAX

    uri = URI.parse(value)
    value if uri.is_a?(URI::HTTPS) && uri.host.present?
  rescue URI::InvalidURIError
    nil
  end

  # ---- event → convite de evento (rodada 2) ----
  # { name, description?, startTime (s), endTime? (s), location?: { name }, extraGuestsAllowed: false }. O tipo
  # (RichMessages::Types::Event) valida datas e textos; aqui só cabe o que o motor aceita.
  def event
    return @event if defined?(@event)

    @event = build_event
  end

  def build_event
    type = RichMessages::Types::Event.new(@rich.to_hash.stringify_keys)
    return unless type.error_for(@body).nil?

    { name: @body, description: @rich[:description].presence, startTime: type.start_at.to_i, endTime: type.end_at&.to_i,
      location: (@rich[:location_name].presence && { name: @rich[:location_name] }), extraGuestsAllowed: false }.compact
  end
end

# A imagem do cartão de prévia do botão de link (`rich_message.image_url` do link_button, chat#1709 rodada 2) nunca vai
# ao motor como o endereço que quem criou a mensagem mandou (revisão da rodada 2: SSRF). O motor WAHA busca a imagem a
# partir da VPS e a manda ao WhatsApp do destinatário; um endereço da rede interna (IP privado, 169.254.x, localhost
# com TLS) sairia como imagem para um número de quem montou a mensagem.
#
# Callback `before_create` de Message: com a flag `whatsapp_rich_native`, na caixa WAHA comum ou na do WhatsApp (o
# plano B do Híbrido), o chat2you baixa a imagem pelo SafeFetch (o mesmo do avatar: recusa rede privada e revalida cada
# redirecionamento; só https, teto de tamanho e de tempo, só PNG, JPEG ou WebP) e guarda uma cópia no storage. O
# `image_url` da mensagem passa a ser o endereço PÚBLICO dessa cópia, na própria instalação (FRONTEND_URL). Falhou o
# download: o `image_url` sai (log com a classe do erro) e o botão segue como texto com a prévia automática do site.
# Sem a flag, ou noutra caixa, nada muda (como na main, que nem lê o campo).
#
# `own(url, account)`: a cópia nossa por trás do endereço, ou nil. Waha::RichPayload só monta o cartão com ela, e manda
# ao motor o content-type real dela.
module Waha::RichNative::PreviewImage
  FIELD = 'image_url'.freeze
  TYPE = 'link_button'.freeze
  MAX_BYTES = 5 * 1024 * 1024
  TOTAL_SECONDS = 5
  OPEN_SECONDS = 2
  CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze
  SCHEMES = %w[https].freeze
  ACCOUNT_KEY = 'c2y_preview_account_id'.freeze
  BLOB_SEGMENTS = %w[rails active_storage blobs].freeze
  BLOB_ROUTES = %w[redirect proxy].freeze

  module_function

  def before_create(message)
    rich = link_button_with_image(message)
    return if rich.nil? || own(rich[FIELD], message.account)

    copy = rehost(rich[FIELD], message.account)
    replace!(message, copy ? rich.merge(FIELD => copy) : rich.except(FIELD))
  rescue StandardError => e
    # Nunca interrompe a criação: sem a cópia, o campo sai e o botão segue como texto.
    Rails.logger.error("[waha] rich native preview image #{e.class}")
    replace!(message, rich.except(FIELD)) if rich.is_a?(Hash)
  end

  # O `rich_message` do botão de link com imagem, quando a cópia se aplica (flag e caixa); senão, nil.
  def link_button_with_image(message)
    rich = message.content_attributes.to_h[RichMessages::KEY]
    return unless rich.is_a?(Hash) && rich['type'] == TYPE && rich[FIELD].present?

    rich if applicable_inbox?(message.inbox) && Waha::RichNative.enabled?(message.account)
  end

  def replace!(message, rich)
    message.content_attributes = message.content_attributes.to_h.merge(RichMessages::KEY => rich)
  end

  def applicable_inbox?(inbox)
    return false if inbox.nil?
    return true if inbox.channel_type == 'Channel::Whatsapp'

    inbox.channel_type == 'Channel::Api' && inbox.channel.try(:waha_provider?) ? true : false
  end

  # O endereço público da cópia, ou nil quando o download falhou.
  def rehost(url, account)
    SafeFetch.fetch(url.to_s, max_bytes: MAX_BYTES, open_timeout: OPEN_SECONDS, read_timeout: TOTAL_SECONDS,
                              total_timeout: TOTAL_SECONDS, schemes: SCHEMES, allowed_content_type_prefixes: [],
                              allowed_content_types: CONTENT_TYPES) do |file|
      public_url(store(file, account))
    end
  rescue StandardError => e
    Rails.logger.warn("[waha] rich native preview image account=#{account.id} #{e.class}")
    nil
  end

  def store(file, account)
    ActiveStorage::Blob.create_and_upload!(io: file.tempfile, filename: file.original_filename.presence || 'preview',
                                           content_type: file.content_type, metadata: { ACCOUNT_KEY => account.id })
  end

  def public_url(blob)
    base = frontend
    Rails.application.routes.url_helpers.rails_blob_url(blob, host: base.host, protocol: base.scheme, port: base.port)
  end

  # A cópia nossa (blob desta conta, de um tipo aceito) por trás do endereço, ou nil.
  def own(url, account)
    blob = blob_for(url)
    blob if blob && blob.metadata[ACCOUNT_KEY].to_s == account.id.to_s && CONTENT_TYPES.include?(blob.content_type)
  end

  def blob_for(url)
    uri = URI.parse(url.to_s.strip)
    return unless same_origin?(uri)

    segments = uri.path.to_s.split('/').reject(&:empty?)
    return unless segments.first(3) == BLOB_SEGMENTS && BLOB_ROUTES.include?(segments[3])

    ActiveStorage::Blob.find_signed(segments[4])
  rescue URI::InvalidURIError, ArgumentError
    nil
  end

  def same_origin?(uri)
    base = frontend
    uri.scheme == base.scheme && uri.host == base.host && uri.port == base.port
  end

  def frontend
    URI.parse(ENV.fetch('FRONTEND_URL', Rails.application.routes.default_url_options[:host]).to_s)
  end
end

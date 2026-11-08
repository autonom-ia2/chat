# Topo com foto, vídeo ou documento numa campanha do WhatsApp oficial (#1382, auditoria M5). Antes, a jornada pedia um
# link digitado e ninguém o conferia no servidor: link vazio passava e cada envio saía com o topo sem arquivo; link que
# não é http(s) só falhava no envio. Agora:
# - sem link, a campanha usa o arquivo guardado no perfil do modelo (`WhatsappTemplateProfile#header_file`), a mesma
#   mídia que foi aprovada; o link do arquivo é gerado na hora do disparo (nunca fica guardado na campanha, porque
#   expira);
# - com link, ele precisa ser http ou https, ter endereço e o tipo (`media_type`) ser o do topo do modelo;
# - com arquivo escolhido na campanha (#1465, `media_blob`): a referência assinada do upload de mídia dos Modelos
#   (`Manager#upload`), só desta conta, do tipo do topo e do tamanho que a Meta aceita; o link também é gerado no disparo.
#   É o mesmo caminho e a mesma conferência dos cartões do carrossel (`CardMedia`).
# Usado na criação (`CampaignJourney::WhatsappCampaignCreator`) e no disparo (`CampaignPauses::WhatsappDispatchGate`).
module Whatsapp::Templates::HeaderMedia
  FORMATS = %w[IMAGE VIDEO DOCUMENT].freeze
  SCHEMES = %w[http https].freeze
  MAX_URL = 2000
  # O disparo de uma campanha grande leva horas; o link do arquivo vale um dia (link assinado do armazenamento).
  URL_TTL = 1.day
  # Tipo e tamanho que a Meta aceita (página "Media" da documentação, lida em 13/10/2026); o mesmo da tela (EscolherArquivo).
  UPLOAD_LIMITS = { 'image/jpeg' => 5.megabytes, 'image/png' => 5.megabytes, 'video/mp4' => 16.megabytes,
                    'application/pdf' => 100.megabytes }.freeze
  # O começo do content_type que cada tipo de topo aceita (o tipo do blob vem dos bytes, no upload).
  MIME_PREFIX = { 'image' => 'image/', 'video' => 'video/', 'document' => 'application/pdf' }.freeze

  # Recusa com `code` estável para a tela.
  class Invalid < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super
    end
  end

  module_function

  # 'image' | 'video' | 'document' quando o topo do modelo é mídia; nil sem topo de mídia.
  def media_type(template)
    header = Array(template&.dig('components')).find { |component| component['type'].to_s.casecmp?('HEADER') }
    format = header&.dig('format').to_s.upcase
    format.downcase if FORMATS.include?(format)
  end

  # O `header` de processed_params conferido e completado com o tipo. O arquivo escolhido na campanha vence o link; sem
  # nenhum dos dois, exige o arquivo no perfil.
  def normalize!(header, template:, inbox:)
    type = media_type(template)
    return header unless type

    header = checked_header!(header, type)
    chosen = header['media_blob'].to_s.strip
    return header.merge('media_url' => '', 'media_blob' => checked_blob!(chosen, type, inbox), 'media_type' => type) if chosen.present?

    url = header['media_url'].to_s.strip
    url.present? ? check_url!(url) : (profile_file(inbox, template) || raise(Invalid, 'header_media_required'))
    header.except('media_blob').merge('media_url' => url, 'media_type' => type)
  end

  def checked_blob!(signed_id, type, inbox)
    raise Invalid, 'header_media_invalid' unless blob_accepted?(ActiveStorage::Blob.find_signed(signed_id), type, inbox.account_id)

    signed_id
  end

  # Arquivo subido pelo upload dos Modelos para esta conta, do tipo pedido ('image' | 'video' | 'document') e do tamanho
  # que a Meta aceita. Também confere o arquivo de cada cartão do carrossel (`CardMedia`).
  def blob_accepted?(blob, type, account_id)
    blob.present? && blob.metadata['account_id'].to_s == account_id.to_s &&
      blob.content_type.to_s.start_with?(MIME_PREFIX.fetch(type)) && upload_allowed?(blob.content_type, blob.byte_size)
  end

  def checked_header!(header, type)
    raise Invalid, 'header_media_url_invalid' unless header.nil? || header.is_a?(Hash)

    header = header.to_h.stringify_keys
    raise Invalid, 'header_media_type_mismatch' if header['media_type'].present? && !header['media_type'].to_s.casecmp?(type)

    header
  end

  def check_url!(url)
    uri = URI.parse(url)
    raise Invalid, 'header_media_url_invalid' unless SCHEMES.include?(uri.scheme) && uri.host.present? && url.length <= MAX_URL
  rescue URI::InvalidURIError
    raise Invalid, 'header_media_url_invalid'
  end

  # O arquivo do topo guardado no perfil do modelo (caixas da mesma WABA dividem o perfil), ou nil.
  def profile_file(inbox, template)
    profile = profile(inbox, template)
    profile&.header_file&.attached? ? profile.header_file : nil
  end

  # O perfil do modelo na WABA da caixa (nome e idioma), ou nil. Também usado pelos cartões do carrossel (#1334).
  def profile(inbox, template)
    WhatsappTemplateProfile.for_inbox(inbox).where(name: template['name'])
                           .detect { |candidate| candidate.language.to_s.casecmp?(template['language'].to_s) }
  end

  def upload_allowed?(content_type, byte_size)
    limit = UPLOAD_LIMITS[content_type.to_s]
    limit.present? && byte_size.to_i.between?(1, limit)
  end

  # Link assinado do arquivo (anexo ou blob) para o envio (vale um dia: o disparo de uma campanha grande leva horas).
  def signed_media(file)
    blob = file.is_a?(ActiveStorage::Blob) ? file : file.blob
    ActiveStorage::Current.url_options = Rails.application.routes.default_url_options if ActiveStorage::Current.url_options.blank?
    { 'media_url' => blob.url(expires_in: URL_TTL), 'media_name' => blob.filename.to_s }
  end

  # { 'media_url' => link assinado, 'media_name' => nome do arquivo, 'media_signed_id', 'media_id'? } para o envio: o arquivo escolhido na campanha
  # (`media_blob`) ou, sem ele, o guardado no perfil do modelo. nil quando o arquivo sumiu ou não serve mais (conferido de
  # novo aqui: a referência pode ter sido gravada por fora da criação).
  def dispatch_media(header, inbox, template)
    chosen = header.is_a?(Hash) ? header['media_blob'].to_s : ''
    return profile_media(inbox, template) if chosen.blank?

    blob = ActiveStorage::Blob.find_signed(chosen)
    dispatch_file(blob, inbox) if blob_accepted?(blob, media_type(template), inbox.account_id)
  end

  def profile_media(inbox, template)
    file = profile_file(inbox, template)
    file && dispatch_file(file.blob, inbox)
  end

  # O arquivo vai à Meta pelo id (`media_id`, subido na caixa que envia: `MetaMediaId`, #2367); sem id, pelo link
  # assinado. A referência assinada do arquivo (`media_signed_id`) fica para a foto do envio (#1717) gravar o endereço
  # permanente do nosso armazenamento. O envio à Meta só lê media_id, media_url, media_type e media_name.
  # Também usado pelos cartões do carrossel (`CardMedia`).
  def dispatch_file(blob, inbox)
    media = signed_media(blob).merge('media_signed_id' => blob.signed_id)
    media_id = Whatsapp::Templates::MetaMediaId.upload(blob, inbox)
    media_id ? media.merge('media_id' => media_id) : media
  end
end

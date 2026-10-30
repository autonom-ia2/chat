# A foto ou o vídeo de cada cartão do carrossel numa campanha (#1334). O topo de um cartão vem de:
#   media_blob   — o arquivo escolhido na campanha: a referência assinada do upload de mídia dos Modelos
#                  (`Manager#upload`), só desta conta, do tipo do cartão (foto JPG/PNG ou vídeo MP4) e do tamanho que a
#                  Meta aceita (`HeaderMedia::UPLOAD_LIMITS`);
#   media_url    — um link http(s) (API);
#   media_stored — nada escolhido: o arquivo aprovado do cartão, guardado no perfil do modelo (`card_files`).
# O link do arquivo é gerado no disparo (`for_dispatch`), uma vez, porque expira.
module Whatsapp::Templates::CardMedia
  Invalid = Whatsapp::Templates::HeaderMedia::Invalid
  FORMATS = %w[IMAGE VIDEO].freeze

  module_function

  # O topo do cartão conferido, como a campanha guarda.
  def header(header, template_card, profile, index, account_id)
    type = format_of(template_card)
    raise Invalid, 'carousel_media_invalid' unless type

    chosen = header['media_blob'].to_s.strip
    return { 'media_blob' => checked_blob!(chosen, type, account_id), 'media_type' => type } if chosen.present?

    url = header['media_url'].to_s.strip
    return { 'media_url' => checked_url!(url), 'media_type' => type } if url.present?
    raise Invalid, 'carousel_media_required' unless profile&.card_file(index)

    { 'media_stored' => true, 'media_type' => type }
  end

  def checked_blob!(signed_id, type, account_id)
    blob = ActiveStorage::Blob.find_signed(signed_id)
    raise Invalid, 'carousel_media_invalid' unless Whatsapp::Templates::HeaderMedia.blob_accepted?(blob, type, account_id)

    signed_id
  end

  def checked_url!(url)
    Whatsapp::Templates::HeaderMedia.check_url!(url)
    url
  rescue Invalid
    raise Invalid, 'carousel_media_invalid'
  end

  # { índice => { 'media_url', 'media_name', 'media_signed_id', 'media_id'? } } dos cartões com arquivo (escolhido ou aprovado); {} sem nenhum;
  # nil quando um arquivo sumiu (a campanha para com template_media_missing).
  def for_dispatch(processed, template, inbox)
    headers = headers_of(processed)
    pending = headers.each_index.select { |index| headers[index]['media_stored'] == true || headers[index]['media_blob'].present? }
    return {} if pending.empty?

    profile = Whatsapp::Templates::HeaderMedia.profile(inbox, template)
    files = pending.index_with { |index| file_for(headers[index], profile, index) }
    return if files.values.any?(&:nil?)

    files.transform_values { |file| dispatch_media(file, inbox) }
  end

  # O id da mídia (ou, sem ele, o link assinado) vai à Meta e a referência assinada fica para a foto do envio (#1717):
  # `HeaderMedia.dispatch_file`. A Meta não a recebe (`SendComponents#card_payload`).
  def dispatch_media(file, inbox)
    Whatsapp::Templates::HeaderMedia.dispatch_file(file.is_a?(ActiveStorage::Blob) ? file : file.blob, inbox)
  end

  # Os arquivos guardados no perfil do modelo, na ordem dos cartões, para a lista de Modelos (#1334). Foto também leva a
  # miniatura (link de leitura assinado, que expira) e a referência do arquivo (#1716), que também expira: a conversa
  # monta a galeria do modelo e manda a referência como um arquivo escolhido (`media_blob`), conferido em `header` como
  # qualquer outro (só desta conta, do tipo e do tamanho certos).
  def listed(profile)
    profile.card_files.map { |file| listed_file(file) }.sort_by { |media| media['card_index'] }
  end

  def listed_file(file)
    row = { 'card_index' => file.blob.metadata['card_index'].to_i, 'file_name' => file.filename.to_s }
    return row unless file.content_type.to_s.start_with?('image/')

    row.merge('preview_url' => Whatsapp::Templates::HeaderMedia.signed_media(file)['media_url'],
              'blob_signed_id' => file.blob.signed_id(expires_in: Whatsapp::Templates::HeaderMedia::URL_TTL))
  end

  def headers_of(processed)
    carousel = processed['carousel'].is_a?(Hash) ? processed['carousel'] : {}
    Array(carousel['cards']).map { |card| card.is_a?(Hash) && card['header'].is_a?(Hash) ? card['header'] : {} }
  end

  def file_for(header, profile, index)
    return ActiveStorage::Blob.find_signed(header['media_blob']) if header['media_blob'].present?

    profile&.card_file(index)
  end

  def format_of(template_card)
    components = Whatsapp::Templates::SendableFormat.hashes(template_card['components'])
    format = components.find { |item| item['type'].to_s.casecmp?('HEADER') }&.dig('format').to_s.upcase
    format.downcase if FORMATS.include?(format)
  end
end

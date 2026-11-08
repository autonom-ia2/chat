# Arquivo de exemplo do topo ou de um cartão de modelo (Modelos e "Trocar" da campanha): sobe para a Meta (o handle da
# análise) e fica guardado no ActiveStorage (o arquivo do envio).
#
# O tipo do arquivo é o que o conteúdo diz (assinatura dos bytes, Marcel, o mesmo do ActiveStorage), nunca o nome nem o
# que o navegador declarou (#1334: um texto chamado .png não passa).
# Vídeo que o WhatsApp não entrega (HEVC, .mov; `VideoForMeta`, #2370) não sobe aqui: a conversão vai para um job
# (`VideoConversion`) e a resposta é `{ conversion_id: }`, que a tela acompanha até o resultado de `store`.
class Whatsapp::Templates::MediaUpload
  def initialize(inbox:, account_user:)
    @inbox = inbox
    @account_user = account_user
  end

  def perform(file)
    content_type = Marcel::MimeType.for(file)
    file.rewind
    media = Whatsapp::Templates::VideoForMeta.ready(file, content_type)
    return store(media) if media

    { conversion_id: Whatsapp::Templates::VideoConversion.start(inbox: @inbox, account_user: @account_user, file: file) }
  end

  def store(media)
    unless Whatsapp::Templates::HeaderMedia.upload_allowed?(media.content_type, media.size)
      raise Whatsapp::Templates::Manager::Refused, 'media_invalid'
    end

    handle = Whatsapp::Templates::MetaClient.new(inbox: @inbox).upload_media(**media.to_h)
    media.io.rewind
    blob = ActiveStorage::Blob.create_and_upload!(io: media.io, filename: media.file_name, content_type: media.content_type,
                                                  identify: false, metadata: { 'account_id' => @inbox.account_id })
    { handle: handle, blob_signed_id: blob.signed_id, file_name: blob.filename.to_s, content_type: blob.content_type,
      byte_size: blob.byte_size }
  end
end

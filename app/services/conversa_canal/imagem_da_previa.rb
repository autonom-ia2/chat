# A imagem da prévia de link (#1702) é baixada pelo servidor (SafeFetch, mesmas travas do HTML) e guardada como
# anexo da própria mensagem. O painel mostra a cópia nossa: o site não fica sabendo o IP do atendente nem quando
# ele leu a conversa, como aconteceria com a imagem puxada direto do site. Só foto comum (JPEG, PNG, WebP, GIF),
# conferida pelo conteúdo do arquivo e não só pelo cabeçalho; SVG fica de fora (pode levar script). Até 1 MB.
class ConversaCanal::ImagemDaPrevia
  TIPOS = %w[image/jpeg image/png image/webp image/gif].freeze
  MAX_BYTES = 1.megabyte
  ANEXO = :previa_de_link_imagem

  def initialize(message, url)
    @message = message
    @url = url
  end

  # => o caminho da imagem no nosso servidor, ou nil quando não deu (sem imagem, a prévia sai só com texto).
  def guardar
    return unless ConversaCanal::LeitorDeOpenGraph.endereco_permitido?(@url)

    SafeFetch.fetch(@url, **ConversaCanal::LeitorDeOpenGraph.opcoes_do_fetch(tipos: TIPOS, max_bytes: MAX_BYTES)) do |resultado|
      tipo = Marcel::MimeType.for(resultado.tempfile)
      next unless TIPOS.include?(tipo)

      resultado.tempfile.rewind
      anexo = @message.public_send(ANEXO)
      anexo.attach(io: resultado.tempfile, filename: "previa-#{@message.id}", content_type: tipo)
      Rails.application.routes.url_helpers.rails_blob_path(anexo.blob, only_path: true)
    end
  end
end

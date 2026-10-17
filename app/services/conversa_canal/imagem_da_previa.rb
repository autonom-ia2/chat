# A imagem da prévia de link (#1702) é baixada pelo servidor (SafeFetch, mesmas travas do HTML) e guardada como
# anexo da própria mensagem. O painel mostra a cópia nossa: o site não fica sabendo o IP do atendente nem quando
# ele leu a conversa, como aconteceria com a imagem puxada direto do site. Só foto comum (JPEG, PNG, WebP, GIF),
# conferida pelo conteúdo do arquivo e não só pelo cabeçalho; SVG fica de fora (pode levar script). Até 1 MB.
# Cada endereço de imagem é baixado no máximo uma vez a cada 24 h (o mesmo prazo da página): as próximas mensagens
# copiam o arquivo que já está conosco, e uma imagem recusada fica recusada. Sem isso, repetir a mesma mensagem fazia
# o servidor buscar a imagem de novo a cada vez, fora da cota de leituras da conta (revisão adversarial, 17/10).
# A lembrança é por conta: uma conta nunca lê arquivo guardado por outra.
class ConversaCanal::ImagemDaPrevia
  TIPOS = %w[image/jpeg image/png image/webp image/gif].freeze
  MAX_BYTES = 1.megabyte
  ANEXO = :previa_de_link_imagem
  VALIDADE = 24.hours
  SEM_IMAGEM = 'sem_imagem'.freeze

  def initialize(message, url)
    @message = message
    @url = url
  end

  # => o caminho da imagem no nosso servidor, ou nil quando não deu (sem imagem, a prévia sai só com texto).
  def guardar
    guardada = Rails.cache.read(chave)
    return if guardada == SEM_IMAGEM

    # O arquivo guardado pode ter saído (mensagem apagada): aí baixa de novo em vez de ficar sem imagem até vencer.
    copia = copiar(guardada) if guardada.present?
    return copia if copia

    baixar.tap { |caminho| lembrar(caminho ? anexo.blob.id : SEM_IMAGEM) }
  rescue SafeFetch::Error
    lembrar(SEM_IMAGEM)
    raise
  end

  private

  def chave
    "conversa_canal:previa_de_link:imagem:#{@message.account_id}:#{Digest::SHA256.hexdigest(@url)}"
  end

  def lembrar(valor)
    Rails.cache.write(chave, valor, expires_in: VALIDADE)
  end

  def anexo
    @message.public_send(ANEXO)
  end

  def baixar
    return unless ConversaCanal::LeitorDeOpenGraph.endereco_permitido?(@url)

    SafeFetch.fetch(@url, **ConversaCanal::LeitorDeOpenGraph.opcoes_do_fetch(tipos: TIPOS, max_bytes: MAX_BYTES)) do |resultado|
      tipo = Marcel::MimeType.for(resultado.tempfile)
      next unless TIPOS.include?(tipo)

      resultado.tempfile.rewind
      anexar(resultado.tempfile, tipo)
    end
  end

  # Cópia do arquivo que já está no nosso armazenamento: cada mensagem tem o seu (apagar uma não apaga a das outras).
  def copiar(blob_id)
    blob = ActiveStorage::Blob.find_by(id: blob_id)
    return if blob.nil?

    blob.open { |arquivo| anexar(arquivo, blob.content_type) }
  rescue ActiveStorage::FileNotFoundError
    nil
  end

  def anexar(io, tipo)
    anexo.attach(io: io, filename: "previa-#{@message.id}", content_type: tipo)
    Rails.application.routes.url_helpers.rails_blob_path(anexo.blob, only_path: true)
  end
end

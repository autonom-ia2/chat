# O documento que o cliente manda (#2716). O ex.14 dos termos de aceite fala em "foto ou PDF" no passo 2 ("A cada foto
# ou PDF que chega") e no 5 ("2 dias sem documento novo"). Foto é o anexo de imagem com arquivo; PDF é o arquivo
# `application/pdf`. Áudio, vídeo, localização, figurinha e outro arquivo não são documento. O filtro
# `mensagem.tem_anexo` lê daqui (`mensagem?`, em Ruby), e o valor `conversa.cliente_mandou_documento` do "esperar até"
# (G46, Resposta) lê o `escopo`, a mesma régua em SQL: a régua mora num lugar só.
#
# A figurinha do WhatsApp chega como `image` (`file_content_type` junta image e sticker). A marca dela é
# `meta.is_sticker`, gravada no recebimento: ConversaCanal::FigurinhaRecebida (Cloud, 360dialog e Híbrido) e
# Waha::RichNative::Inbound::Media (caixa WAHA).
module Autonomia::Automacao::FotoOuPdf
  module_function

  PDF = 'application/pdf'.freeze

  def anexo?(anexo)
    return false unless anexo.file.attached?

    case anexo.file_type.to_s
    when 'image' then !figurinha?(anexo)
    when 'file' then anexo.file.content_type.to_s.downcase.split(';').first == PDF
    else false
    end
  end

  def figurinha?(anexo) = anexo.meta.to_h[ConversaCanal::FigurinhaRecebida::CHAVE] == true

  def mensagem?(mensagem) = mensagem.attachments.includes(file_attachment: :blob).any? { |anexo| anexo?(anexo) }

  # As mensagens de `mensagens` com pelo menos uma foto ou um PDF: a régua de `anexo?` numa consulta só, sem carregar
  # anexo nenhum. Só lê o tipo e o arquivo, nada do conteúdo.
  def escopo(mensagens)
    da_mensagem = ::Attachment.where('attachments.message_id = messages.id').where(com_arquivo.arel.exists)
    figurinha = ConversaCanal::FigurinhaRecebida::CHAVE
    foto = da_mensagem.where(file_type: :image).where("COALESCE(attachments.meta ->> ?, 'false') <> 'true'", figurinha)
    mensagens.where(foto.or(da_mensagem.where(file_type: :file).where(com_arquivo(PDF).arel.exists)).arel.exists)
  end

  # O arquivo do anexo da linha de fora (`attachments`); com `tipo`, só o desse content type (sem os parâmetros, em
  # minúscula, como `anexo?`).
  def com_arquivo(tipo = nil)
    arquivo = ::ActiveStorage::Attachment.where(record_type: 'Attachment', name: 'file')
                                         .where('active_storage_attachments.record_id = attachments.id')
    return arquivo unless tipo

    arquivo.joins(:blob).where("LOWER(SPLIT_PART(active_storage_blobs.content_type, ';', 1)) = ?", tipo)
  end
end

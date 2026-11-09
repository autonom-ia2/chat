# O documento que o cliente manda (#2716). O ex.14 dos termos de aceite fala em "foto ou PDF" no passo 2 ("A cada foto
# ou PDF que chega") e no 5 ("2 dias sem documento novo"). Foto é o anexo de imagem com arquivo; PDF é o arquivo
# `application/pdf`. Áudio, vídeo, localização, figurinha e outro arquivo não são documento. O filtro
# `mensagem.tem_anexo` lê daqui, e a espera pelo próximo documento (G46) usa a mesma régua.
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
end

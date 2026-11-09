# O documento que o cliente manda (#2716). O ex.14 dos termos de aceite fala em "foto ou PDF" no passo 2 ("A cada foto
# ou PDF que chega") e no 5 ("2 dias sem documento novo"). Foto é o anexo de imagem; PDF é o arquivo
# `application/pdf`. Áudio, vídeo, localização e outro arquivo não são documento. O filtro `mensagem.tem_anexo` lê
# daqui, e a espera pelo próximo documento (G46) usa a mesma régua.
module Autonomia::Automacao::FotoOuPdf
  module_function

  PDF = 'application/pdf'.freeze

  def anexo?(anexo)
    case anexo.file_type.to_s
    when 'image' then true
    when 'file' then anexo.file.attached? && anexo.file.content_type.to_s.downcase.split(';').first == PDF
    else false
    end
  end

  def mensagem?(mensagem) = mensagem.attachments.includes(file_attachment: :blob).any? { |anexo| anexo?(anexo) }
end

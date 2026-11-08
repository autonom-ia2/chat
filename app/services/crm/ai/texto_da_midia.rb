# O texto de um anexo como as IAs do CRM o leem (extraído do Crm::Ai::ContextBuilder). Uma fonte só: a IA de etapa,
# a memória e (IA entende a conversa F4) a IA de assunto leem a mesma coisa da `attachment.meta`.
#
# `pdf: true` (F4, flag `crm_ia_leitor_de_midia`): o PDF lido pelo Crm::Ai::LeitorDeMidia vira
# "[documento <nome>]: <texto>", cortado em MAX_CARACTERES_DO_PDF; o PDF sem texto legível diz isso. Sem ele, o PDF é
# "[documento recebido]", como antes.
module Crm::Ai::TextoDaMidia
  MAX_CARACTERES_DO_PDF = 1_500
  MAX_NOME = 120

  def self.fragmento(attachment, pdf: false)
    meta = attachment.meta.to_h
    case attachment.file_type.to_s
    when 'audio' then audio(meta)
    when 'image' then imagem(meta)
    when 'video' then '[vídeo recebido]'
    when 'file' then pdf ? documento(attachment, meta) : '[documento recebido]'
    end
  end

  # Só o que foi lido de verdade (transcrição, descrição ou texto do PDF); nil quando o anexo não tem texto lido. É o
  # que a IA de assunto recebe: anexo sem leitura não vira mensagem para ela.
  def self.lido(attachment)
    tipo = Crm::Ai::LeitorDeMidia.tipo(attachment)
    return if tipo.nil? || attachment.meta.to_h[Crm::Ai::LeitorDeMidia::CHAVE[tipo]].to_s.strip.blank?

    fragmento(attachment, pdf: true)
  end

  def self.audio(meta)
    texto = meta['transcribed_text'].to_s.strip
    texto.present? ? "[áudio transcrito]: #{texto.truncate(Crm::Ai::Config::TRANSCRIPT_MAX_CHARS)}" : '[áudio recebido, não transcrito]'
  end

  def self.imagem(meta)
    texto = meta['ai_caption'].to_s.strip
    texto.present? ? "[imagem]: #{texto.truncate(Crm::Ai::Config::CAPTION_MAX_CHARS)}" : '[imagem recebida]'
  end

  def self.documento(attachment, meta)
    texto = meta['ai_text'].to_s.strip
    return "[documento #{nome(attachment)}]: #{texto.truncate(MAX_CARACTERES_DO_PDF)}" if texto.present?
    return "[documento #{nome(attachment)}: sem texto legível]" if meta[Crm::Ai::LeitorDeMidia::MARCA[:pdf]]

    '[documento recebido]'
  end

  def self.nome(attachment)
    attachment.file.attached? ? attachment.file.filename.to_s.squish.first(MAX_NOME) : 'sem nome'
  end
end

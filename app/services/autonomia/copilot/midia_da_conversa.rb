# #3198 — o arquivo que alguém mandou na conversa entra no que o copiloto da equipe lê.
#
# O copiloto não lê arquivo sozinho: reaproveita o texto que a plataforma já guarda no anexo.
# - Áudio, foto e PDF: o leitor de mídia do CRM (Crm::Ai::LeitorDeMidia) lê na chegada e grava em
#   `transcribed_text`, `ai_caption` e `ai_text`. O que ele ainda não leu (mensagem antiga, caixa sem CRM),
#   o copiloto pede a ele aqui, nas mensagens mais novas: é o mesmo leitor, com a mesma reserva e o mesmo teto
#   do dia, então cada arquivo é pago uma vez só, para todas as IAs.
# - Word, Excel, CSV, texto e JSON: os extratores da base de conhecimento, no nosso servidor e sem IA
#   (Autonomia::Guide::LeitorDeMidia#ler, com cache).
#
# O que não dá para ler (vídeo, tipo que não lemos, leitura que falhou) entra como aviso, para o copiloto dizer que
# não leu em vez de fingir que o arquivo não existe. Falha de leitura nunca derruba a resposta do copiloto.
class Autonomia::Copilot::MidiaDaConversa
  # Um arquivo grande não pode tomar a conversa inteira: cada anexo entra cortado.
  MAX_POR_ANEXO = 1_500
  # Quantas mensagens, das mais novas, podem ter mídia lida agora. O resto já costuma vir lido da chegada.
  MAX_MENSAGENS_LIDAS_NA_HORA = 5
  # O texto que outro leitor já gravou no anexo, na ordem de preferência.
  CHAVES = %w[transcribed_text ai_caption ai_text guia_texto_da_imagem].freeze
  ROTULOS = { 'audio' => 'Áudio', 'image' => 'Imagem', 'video' => 'Vídeo', 'file' => 'Arquivo' }.freeze
  NAO_LIDO = 'não consegui ler'.freeze
  VIDEO = 'o copiloto ainda não assiste vídeo'.freeze
  TIPO_NAO_LIDO = 'o copiloto ainda não lê este tipo de arquivo'.freeze

  def initialize(account:)
    @account = account
  end

  # Lê agora, pelo leitor do CRM, a mídia ainda não lida das mensagens mais novas.
  def ler_pendentes(messages)
    com_pendente = messages.select { |message| message.attachments.any? { |anexo| Crm::Ai::LeitorDeMidia.pendente?(anexo) } }
    com_pendente.last(MAX_MENSAGENS_LIDAS_NA_HORA).each { |message| ler_em_linha(message) }
  end

  # -> String com uma linha por anexo da mensagem, ou vazia.
  def texto(message)
    message.attachments.map { |anexo| linha(anexo) }.join(' ')
  end

  private

  def ler_em_linha(message)
    Crm::Ai::LeitorDeMidia.ler_em_linha(message)
    message.attachments.reload
  rescue StandardError => e
    Rails.logger.warn("[autonomia][copilot][midia] leitura_falhou mensagem=#{message.id} erro=#{e.class}")
  end

  def linha(anexo)
    rotulo = ROTULOS.fetch(anexo.file_type.to_s, 'Anexo')
    rotulo = "#{rotulo} #{nome(anexo)}" if anexo.file_type.to_s == 'file'
    "[#{rotulo}: #{conteudo(anexo).to_s.squish.truncate(MAX_POR_ANEXO)}]"
  end

  def conteudo(anexo)
    gravado = CHAVES.lazy.map { |chave| anexo.meta.to_h[chave].to_s.strip }.find(&:present?)
    return gravado if gravado.present?
    return VIDEO if anexo.file_type.to_s == 'video'
    return documento(anexo) if anexo.file_type.to_s == 'file'

    NAO_LIDO
  end

  def documento(anexo)
    blob = anexo.file&.blob
    return TIPO_NAO_LIDO unless blob && Autonomia::Guide::LeitorDeMidia.tipo(blob.content_type) == 'documento'
    return NAO_LIDO if blob.byte_size > Autonomia::Agents::Config::MAX_DOCUMENT_BYTES

    Autonomia::Guide::LeitorDeMidia.new(account: @account).ler(blob).presence || NAO_LIDO
  rescue StandardError => e
    Rails.logger.warn("[autonomia][copilot][midia] documento_falhou anexo=#{anexo.id} erro=#{e.class}")
    NAO_LIDO
  end

  def nome(anexo)
    anexo.file&.blob&.filename.to_s
  end
end

# IA entende a conversa, F4 — leitor de mídia na chegada (flag de conta `crm_ia_leitor_de_midia`).
#
# Antes, a IA de assunto descartava a mensagem sem texto (áudio, foto ou PDF sozinhos não existiam para ela), a leitura
# de mídia (Crm::Ai::MediaEnricher) só rodava dentro da avaliação de um card que já existia, e PDF nunca era lido. Com a
# flag, a mensagem com anexo é lida UMA vez, na chegada, e todas as IAs leem o mesmo resultado na `attachment.meta`:
#   áudio  → `transcribed_text` (a chave do EE e dos Agentes IA; já transcrito, não paga de novo)
#   imagem → `ai_caption` (Crm::Ai::VisionCaptioner, feature `midia`)
#   PDF    → `ai_text`: a camada de texto, pelo mesmo processador dos Agentes IA
#            (Autonomia::Agents::Knowledge::Processors::Pdf, chamado como está, sem OCR), em NFC, cortada em
#            MAX_CARACTERES_DO_PDF. PDF escaneado (sem camada de texto) fica sem texto.
# A falha esperada (FALHAS_DA_LEITURA) também marca o anexo como lido (`crm_ai_*_done`, como o MediaEnricher): não tenta de
# novo para sempre. Erro interno propaga e não marca.
#
# Quem chama: o job da chegada (Crm::Ai::LerMidiaJob, pelo ConversationObserverListener) e, antes de perguntar o
# assunto, o IdentifyJob em linha (`ler_a_rajada`), porque a espera do assunto na ordem do turno é curta. A trava por
# anexo (`with_lock`) faz o segundo esperar o primeiro e encontrar o anexo lido: ninguém paga duas vezes. Com a flag,
# o MediaEnricher da avaliação usa este leitor para as mensagens antigas da janela.
#
# Tetos: MAX_POR_MENSAGEM por tipo e MAX_LEITURAS_POR_DIA por conta (contador no Redis, conta todas as leituras, as
# pagas e as de PDF). Passou do teto do dia: não lê, não marca e registra no log.
#
# Sem a flag (ou com a mídia desligada na instalação): nada muda. Nunca loga o conteúdo do anexo.
class Crm::Ai::LeitorDeMidia
  FLAG = 'crm_ia_leitor_de_midia'.freeze
  MAX_POR_MENSAGEM = { audio: 3, imagem: 4, pdf: 2 }.freeze
  MAX_LEITURAS_POR_DIA = 500
  MAX_CARACTERES_DO_PDF = 8_000
  # Quantas mensagens do cliente, até a mensagem perguntada, a leitura em linha olha (a janela da IA de assunto).
  MAX_MENSAGENS_DA_RAJADA = Crm::Subjects::MAX_MENSAGENS
  CHAVE = { audio: 'transcribed_text', imagem: 'ai_caption', pdf: 'ai_text' }.freeze
  MARCA = { audio: 'crm_ai_audio_done', imagem: 'crm_ai_image_done', pdf: 'crm_ai_pdf_done' }.freeze
  PAGOS = %i[audio imagem].freeze
  # As falhas esperadas de uma leitura, que marcam o anexo como lido (sem texto): rede, a API da IA (o cliente da
  # transcrição e o da visão) e o arquivo ilegível. Qualquer outro erro é nosso: propaga, e o anexo fica para depois.
  FALHAS_DA_LEITURA = [
    *Crm::Ai::ResponsesClient::NETWORK_ERRORS, Faraday::Error, OpenAI::Error,
    Crm::Ai::ResponsesClient::Error, Crm::Ai::TranscriptionClient::Error,
    ActiveStorage::FileNotFoundError, ActiveStorage::IntegrityError,
    Autonomia::Agents::Knowledge::Processors::Base::ExtractionError, Autonomia::Agents::Knowledge::Processors::Base::UnsupportedFormat
  ].freeze

  def self.ligada?(account)
    account.present? && account.feature_enabled?(FLAG) && Crm::Ai::Config.media_enabled?
  end

  # A mensagem nova (dos dois lados, não privada) com anexo, numa caixa com o CRM ligado: lê em job, na fila high.
  def self.ler_depois(message)
    return if message.private? || !ligada?(message.account) || !message.attachments.exists?
    return unless Crm::InboxSetting.exists?(account_id: message.account_id, inbox_id: message.inbox_id, crm_enabled: true)

    Crm::Ai::LerMidiaJob.perform_later(message.id)
  end

  # Em linha, antes de a IA de assunto perguntar: as mensagens do cliente até `message` que têm anexo. Uma falha aqui
  # não impede a pergunta do assunto (ela segue com o que já foi lido).
  def self.ler_a_rajada(conversation, message)
    return unless ligada?(conversation.account)

    conversation.messages.incoming.where(id: ..message.id).where(com_anexo)
                .reorder(id: :desc).limit(MAX_MENSAGENS_DA_RAJADA).each { |mensagem| new(mensagem).perform }
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    Rails.logger.error("[crm][midia] leitura_em_linha_falhou conversa=#{conversation.id} mensagem=#{message.id} erro=#{e.class}")
  end

  def self.com_anexo = Attachment.where('attachments.message_id = messages.id').arel.exists

  # A mensagem tem anexo com texto lido (transcrição, descrição ou texto do PDF): só essa entra na janela da IA de
  # assunto. Anexo sem leitura (vídeo, PDF escaneado, leitura que falhou) não ocupa a vaga de uma mensagem com texto.
  def self.com_anexo_lido
    lidos = CHAVE.values.map { |chave| Attachment.where("NULLIF(BTRIM(attachments.meta ->> ?), '') IS NOT NULL", chave) }.reduce(:or)
    lidos.where('attachments.message_id = messages.id').arel.exists
  end

  def self.tipo(attachment)
    case attachment.file_type.to_s
    when 'audio' then :audio
    when 'image' then :imagem
    when 'file' then :pdf if pdf?(attachment)
    end
  end

  # PDF: o tipo do arquivo e o tamanho das regras dos Agentes IA (o `file_type` do Chatwoot para PDF é o genérico `file`).
  def self.pdf?(attachment)
    blob = attachment.file&.blob
    return false if blob.blank?

    tipo = blob.content_type.to_s.downcase.split(';').first
    Autonomia::Agents::Config::DOCUMENT_CONTENT_TYPES.include?(tipo) && blob.byte_size <= Autonomia::Agents::Config::MAX_DOCUMENT_BYTES
  end

  def self.pendente?(attachment)
    tipo = tipo(attachment)
    return false if tipo.nil?

    meta = attachment.meta.to_h
    meta[CHAVE[tipo]].to_s.strip.blank? && !meta[MARCA[tipo]]
  end

  def initialize(message, pipeline: nil)
    @message = message
    @account = message.account
    @pipeline = pipeline
  end

  # -> quantos anexos foram lidos agora.
  def perform
    return 0 unless self.class.ligada?(@account)

    escolhidos.count { |attachment| ler(attachment) }
  end

  # Um anexo, sob a trava dele. true quando leu agora; false quando já estava lido, não é de um tipo lido, falta a
  # credencial da conta ou passou do teto do dia.
  def ler(attachment)
    tipo = self.class.tipo(attachment)
    return false if tipo.nil?

    attachment.with_lock do
      next false unless self.class.pendente?(attachment) && credencial_para?(tipo) && cabe_no_dia?

      guardar(attachment, tipo, ler_texto(attachment, tipo))
      true
    end
  end

  # Os primeiros de cada tipo, até o teto por mensagem, que ainda não foram lidos. Todo consumidor (o job da chegada, a
  # leitura em linha e o Crm::Ai::MediaEnricher da avaliação) lê por esta seleção.
  def escolhidos
    @message.attachments.reorder(:id).group_by { |attachment| self.class.tipo(attachment) }
            .flat_map { |tipo, anexos| tipo ? anexos.first(MAX_POR_MENSAGEM[tipo]) : [] }
            .select { |attachment| self.class.pendente?(attachment) }
  end

  private

  def credencial_para?(tipo)
    PAGOS.exclude?(tipo) || credencial.present?
  end

  def credencial
    @credencial = Crm::Ai::CredentialResolver.new(account: @account).resolve unless defined?(@credencial)
    @credencial
  end

  def cabe_no_dia?
    chave = "crm:leitor_de_midia:#{@account.id}:#{Time.current.utc.to_date.iso8601}"
    total = Redis::Alfred.incr(chave)
    Redis::Alfred.expire(chave, 2.days.to_i) if total == 1
    return true if total <= MAX_LEITURAS_POR_DIA

    Rails.logger.warn("[crm][midia] teto_do_dia conta=#{@account.id} mensagem=#{@message.id}")
    false
  end

  def ler_texto(attachment, tipo)
    case tipo
    when :audio then Crm::Ai::TranscriptionClient.new(credential: credencial).transcribe(attachment)
    when :imagem then Crm::Ai::VisionCaptioner.new(client: cliente_de_visao).caption(attachment)
    when :pdf then texto_do_pdf(attachment)
    end
  rescue *FALHAS_DA_LEITURA => e
    Rails.logger.warn("[crm][midia] leitura_falhou tipo=#{tipo} anexo=#{attachment.id} erro=#{e.class}")
    nil
  end

  def cliente_de_visao
    Crm::Ai::ResponsesClient.new(credential: credencial, feature: 'midia', account: @account, pipeline: @pipeline)
  end

  def texto_do_pdf(attachment)
    fonte = Autonomia::Agents::Operate::MessageMedia::SourceLike.new(attachment.file, attachment.file.blob.filename.to_s, 'pdf')
    texto = Autonomia::Agents::Knowledge::Processors::Pdf.new(fonte, ocr: false).extract.to_s
    texto.unicode_normalize(:nfc).strip.first(MAX_CARACTERES_DO_PDF)
  end

  def guardar(attachment, tipo, texto)
    meta = attachment.meta.to_h
    meta = meta.merge(CHAVE[tipo] => texto.to_s) if texto.present?
    attachment.update!(meta: meta.merge(MARCA[tipo] => true, 'crm_ai_enriched_at' => Time.current.iso8601))
  end
end

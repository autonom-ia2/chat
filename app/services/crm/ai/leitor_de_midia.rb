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
#
# Falha da leitura (#2109), ver Crm::Ai::FalhaDaMidia: a definitiva marca o anexo como lido sem texto, com o motivo; a
# passageira não marca, agenda a próxima tentativa no anexo e sobe FalhaPassageira para o LerMidiaJob tentar de novo.
# Até a próxima tentativa vencer, ninguém lê (a leitura em linha e a da avaliação não gastam tentativa). Depois das
# duas do job, quem tenta é a varredura (Crm::Ai::RelerMidiaPendenteJob), enquanto a mensagem tiver até 48 h; mais
# velha que isso, a falha passageira marca `expirado`; o `expirado` que falha de novo em MAX_RELEITURAS_DO_EXPIRADO
# releituras vira `expirado_esgotado` (definitiva). Erro interno propaga e não marca.
#
# Releitura (`releitura:`), decisão do Rodrigo (23/10/2026):
#   :mensagem_nova chegou mensagem na conversa: o job da chegada relê também o anexo marcado sem texto que não tem falha
#                  definitiva, de qualquer idade — o `expirado` e o marcado antes do #2109, quando toda falha marcava. A
#                  leitura em linha da IA de assunto não espera por isso: lê só o nunca lido e enfileira a releitura
#                  na fila low.
#   :varredura     a varredura dos últimos 2 dias relê só o marcado sem motivo (antes do #2109); o `expirado` não.
# A avaliação do card (MediaEnricher, também a do card parado) não relê: só lê o que nunca foi lido.
#
# Arquivo que ainda não chegou ao storage (ActiveStorage::FileNotFoundError) não é falha da leitura: o job da chegada
# roda no commit da mensagem, e o upload do anexo pode terminar depois (corrida). Esse anexo não é marcado e não gasta
# o teto do dia; o erro sobe para quem chamou tentar de novo (o LerMidiaJob, com espera). Só na última tentativa
# (`ultima_tentativa: true`) o anexo é marcado sem texto, com aviso no log.
#
# Quem chama: o job da chegada (Crm::Ai::LerMidiaJob, pelo ConversationObserverListener) e, antes de perguntar o
# assunto, o IdentifyJob em linha (`ler_a_rajada`), porque a espera do assunto na ordem do turno é curta. A reserva do
# anexo (Crm::Ai::ReservaDaMidia: trava curta, leitura fora de transação) impede que dois paguem a mesma leitura; a
# leitura em linha espera um pouco o anexo que o job da chegada está lendo. Com a flag, o MediaEnricher da avaliação usa
# este leitor para as mensagens antigas da janela.
#
# Tetos: MAX_POR_MENSAGEM por tipo e MAX_LEITURAS_POR_DIA por conta (Crm::Ai::TetoDaMidia; conta todas as tentativas,
# as pagas, as de PDF e as que falharam). Passou do teto do dia: não lê, não marca e registra no log.
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

  # Um ou mais anexos da mensagem tiveram falha passageira e seguem pendentes: o LerMidiaJob tenta de novo.
  class FalhaPassageira < StandardError; end

  def self.ligada?(account)
    account.present? && account.feature_enabled?(FLAG) && Crm::Ai::Config.media_enabled?
  end

  # A mensagem nova (dos dois lados, não privada) com anexo, numa caixa com o CRM ligado: lê em job, na fila high.
  def self.ler_depois(message)
    return if message.private? || !ligada?(message.account) || !message.attachments.exists?
    return unless Crm::InboxSetting.exists?(account_id: message.account_id, inbox_id: message.inbox_id, crm_enabled: true)

    Crm::Ai::LerMidiaJob.perform_later(message.id)
  end

  # Em linha, antes de a IA de assunto perguntar: as mensagens do cliente até `message` que têm anexo. Lê aqui o que
  # nunca foi lido; o que ficou marcado sem texto por falha que não é definitiva (de qualquer idade: é a conversa ativa)
  # vai para o job, para a releitura não segurar a pergunta. Uma falha aqui não impede a pergunta do assunto.
  def self.ler_a_rajada(conversation, message)
    return unless ligada?(conversation.account)

    ate_em = Crm::Ai::ReservaDaMidia::ESPERA_EM_LINHA.from_now
    conversation.messages.incoming.where(id: ..message.id).where(com_anexo)
                .reorder(id: :desc).limit(MAX_MENSAGENS_DA_RAJADA).each { |mensagem| ler_em_linha(mensagem, ate_em) }
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    Rails.logger.error("[crm][midia] leitura_em_linha_falhou conversa=#{conversation.id} mensagem=#{message.id} erro=#{e.class}")
  end

  # O anexo que outro processo está lendo (o job da chegada): espera o texto até `ate_em`, como a trava longa fazia antes.
  # O arquivo ainda está subindo, ou a API teve falha passageira: os anexos ficam pendentes (o job da chegada ou a
  # varredura leem depois), e as outras mensagens da rajada seguem. A releitura do que ficou marcado sem texto vai para
  # a fila low (Crm::Ai::LerMidiaJob.reler), para não disputar com a entrega de mensagens.
  def self.ler_em_linha(mensagem, ate_em = Crm::Ai::ReservaDaMidia::ESPERA_EM_LINHA.from_now)
    mensagem.attachments.reorder(:id).each do |anexo|
      Crm::Ai::ReservaDaMidia.esperar(anexo, ate_em: ate_em) if Crm::Ai::ReservaDaMidia.lendo?(anexo.meta.to_h)
    end
    new(mensagem).perform
    Crm::Ai::LerMidiaJob.reler(mensagem.id, 'mensagem_nova') if new(mensagem, releitura: :mensagem_nova).escolhidos.any?
  rescue ActiveStorage::FileNotFoundError
    Rails.logger.warn("[crm][midia] arquivo_ainda_nao_chegou origem=em_linha mensagem=#{mensagem.id}")
  rescue FalhaPassageira
    Rails.logger.warn("[crm][midia] falha_passageira_pendente origem=em_linha mensagem=#{mensagem.id}")
  end

  def self.com_anexo =Attachment.where('attachments.message_id = messages.id').arel.exists

  # Para a varredura (Crm::Ai::RelerMidiaPendenteJob): áudio ou foto sem texto, sem motivo de falha (nunca lido, à
  # espera de nova tentativa, ou marcado antes do #2109) e com a nova tentativa já vencida. O PDF fica de fora: é lido
  # aqui mesmo, sem API, e não tem falha passageira. A varredura aplica isto só aos ids de mensagem que já escolheu pelo
  # índice; cada mensagem ainda passa por `escolhidos`.
  def self.midia_para_reler
    sem_texto = CHAVE.values.map { |chave| Attachment.where("NULLIF(BTRIM(attachments.meta ->> ?), '') IS NULL", chave) }.reduce(:merge)
    sem_texto.where(file_type: %i[image audio])
             .where("NOT (COALESCE(attachments.meta, '{}'::jsonb) ? :falha)", falha: Crm::Ai::FalhaDaMidia::FALHA)
             .where("COALESCE((attachments.meta ->> :proxima)::timestamptz, '-infinity') <= now()", proxima: Crm::Ai::FalhaDaMidia::PROXIMA)
  end

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

  # Sem texto e ainda por ler: sem a marca de lido; ou, na releitura, marcado sem falha definitiva (mensagem nova) ou
  # sem motivo nenhum (varredura).
  def self.pendente?(attachment, releitura: false)
    tipo = tipo(attachment)
    return false if tipo.nil?

    meta = attachment.meta.to_h
    return false if meta[CHAVE[tipo]].to_s.strip.present?
    return true unless meta[MARCA[tipo]]

    case releitura
    when :mensagem_nova then Crm::Ai::FalhaDaMidia::FALHAS_DEFINITIVAS.exclude?(meta[Crm::Ai::FalhaDaMidia::FALHA])
    when :varredura then meta[Crm::Ai::FalhaDaMidia::FALHA].nil?
    else false
    end
  end

  # `releitura:` decide O QUE ler (pendente?); `uma_chamada:`, COMO chamar a API. A chegada lê no modo :mensagem_nova
  # com as novas tentativas de sempre. A releitura enfileirada faz uma chamada só por anexo, com o mesmo tempo da
  # chegada (leitura longa termina), e para no primeiro erro passageiro: os outros anexos ficam pendentes para a próxima
  # releitura. Numa queda da API, ela não segura por minutos uma thread do Sidekiq, a mesma da entrega de mensagens.
  def initialize(message, pipeline: nil, ultima_tentativa: false, releitura: false, uma_chamada: false)
    @message = message
    @account = message.account
    @pipeline = pipeline
    @ultima_tentativa = ultima_tentativa
    @releitura = releitura
    @uma_chamada = uma_chamada
    @passageiras = []
  end

  # -> quantos anexos foram lidos agora. Lê os escolhidos (com `uma_chamada:`, até o primeiro erro passageiro); se algum
  # teve falha passageira e segue pendente, sobe FalhaPassageira no fim (os outros já ficaram gravados).
  def perform
    return 0 unless self.class.ligada?(@account)

    lidos = 0
    escolhidos.each do |attachment|
      lidos += 1 if ler(attachment)
      break if @uma_chamada && @api_fora
    end
    raise FalhaPassageira, "mensagem=#{@message.id} anexos=#{@passageiras.join(',')}" if @passageiras.any?

    lidos
  end

  # Um anexo, reservado por uma trava curta e lido fora de transação (Crm::Ai::ReservaDaMidia). true quando leu agora (ou marcou a
  # falha); false quando já estava lido ou em leitura, não é de um tipo lido, está à espera da nova tentativa, falta a
  # credencial da conta, passou do teto do dia ou a falha foi passageira (fica pendente).
  def ler(attachment)
    tipo = self.class.tipo(attachment)
    @dono = tipo && Crm::Ai::ReservaDaMidia.reservar(attachment) { a_ler?(attachment) && credencial_para?(tipo) && cabe_no_dia? }
    return false unless @dono

    gravado = false
    begin
      gravado = ler_reservado(attachment, tipo)
    rescue *Crm::Ai::FalhaDaMidia::FALHAS_DA_LEITURA => e
      falhou(attachment, tipo, e).tap { gravado = true } # se `falhou` não gravar (erro de banco), o ensure libera a marca
    ensure
      Crm::Ai::ReservaDaMidia.liberar(attachment, dono: @dono) unless gravado
    end
  end

  # Os primeiros de cada tipo, até o teto por mensagem, que ainda não foram lidos. Todo consumidor (o job da chegada, a
  # leitura em linha, a varredura e o Crm::Ai::MediaEnricher da avaliação) lê por esta seleção. Anexos já carregados (a
  # varredura pré-carrega anexos e blobs, #2141) não são consultados de novo; a reserva confere tudo sob a trava.
  def escolhidos
    anexos = @message.attachments.loaded? ? @message.attachments.sort_by(&:id) : @message.attachments.reorder(:id)
    anexos.group_by { |attachment| self.class.tipo(attachment) }
          .flat_map { |tipo, do_tipo| tipo ? do_tipo.first(MAX_POR_MENSAGEM[tipo]) : [] }
          .select { |attachment| a_ler?(attachment) }
  end

  private

  def a_ler?(attachment)
    self.class.pendente?(attachment, releitura: @releitura) && !Crm::Ai::FalhaDaMidia.na_espera?(attachment.meta.to_h)
  end

  def credencial_para?(tipo)
    PAGOS.exclude?(tipo) || credencial.present?
  end

  def credencial = defined?(@credencial) ? @credencial : (@credencial = Crm::Ai::CredentialResolver.new(account: @account).resolve)

  def teto = @teto ||= Crm::Ai::TetoDaMidia.new(@account)

  def cabe_no_dia?
    return true if teto.somar <= MAX_LEITURAS_POR_DIA

    Rails.logger.warn("[crm][midia] teto_do_dia conta=#{@account.id} mensagem=#{@message.id}")
    false
  end

  # A leitura reservada: o texto, ou a falha do arquivo que não chegou. -> true (gravou).
  def ler_reservado(attachment, tipo)
    texto = ler_texto(attachment, tipo)
    guardar(attachment, tipo, texto, texto.present? ? {} : { Crm::Ai::FalhaDaMidia::FALHA => 'sem_texto' })
  rescue ActiveStorage::FileNotFoundError
    arquivo_nao_chegou(attachment, tipo)
  end

  def ler_texto(attachment, tipo)
    case tipo
    when :audio then Crm::Ai::TranscriptionClient.new(credential: credencial).transcribe(attachment)
    when :imagem then Crm::Ai::VisionCaptioner.new(client: cliente_de_visao).caption(attachment)
    when :pdf then texto_do_pdf(attachment)
    end
  end

  # Fora da última tentativa do job, sobe (sem marcar) para quem chamou tentar de novo. Na última, marca. Não leu: não
  # conta no teto do dia.
  def arquivo_nao_chegou(attachment, tipo)
    teto.devolver
    raise ActiveStorage::FileNotFoundError unless @ultima_tentativa

    Rails.logger.warn("[crm][midia] arquivo_nao_chegou tipo=#{tipo} anexo=#{attachment.id} mensagem=#{@message.id}")
    guardar(attachment, tipo, nil, { Crm::Ai::FalhaDaMidia::FALHA => 'arquivo_ausente' })
    true
  end

  # Definitiva, ou passageira com a mensagem fora da janela: marca como lido, sem texto, com o motivo (true). Passageira:
  # agenda a próxima tentativa e deixa pendente (false). A tentativa conta no teto do dia (em dia de API lenta, o gasto
  # tem limite).
  def falhou(attachment, tipo, erro)
    falha = Crm::Ai::FalhaDaMidia.new(erro, meta: attachment.reload.meta.to_h, mensagem: @message)
    Rails.logger.warn("[crm][midia] leitura_falhou tipo=#{tipo} conta=#{@account.id} anexo=#{attachment.id} #{falha.para_o_log}")
    @api_fora ||= falha.passageira?
    return guardar(attachment, tipo, nil, falha.motivo) if falha.marca?

    Crm::Ai::ReservaDaMidia.gravar(attachment, dono: @dono) { |meta| meta.merge(falha.espera) }
    @passageiras << attachment.id
    false
  end

  def cliente_de_visao
    novas_tentativas = @uma_chamada ? 0 : Crm::Ai::ResponsesClient::MAX_RETRIES
    Crm::Ai::ResponsesClient.new(credential: credencial, feature: 'midia', account: @account, pipeline: @pipeline,
                                 max_retries: novas_tentativas)
  end

  def texto_do_pdf(attachment)
    fonte = Autonomia::Agents::Operate::MessageMedia::SourceLike.new(attachment.file, attachment.file.blob.filename.to_s, 'pdf')
    texto = Autonomia::Agents::Knowledge::Processors::Pdf.new(fonte, ocr: false).extract.to_s
    texto.unicode_normalize(:nfc).strip.first(MAX_CARACTERES_DO_PDF)
  end

  # Com texto, sai o motivo de uma falha anterior (a releitura deu certo) e a espera; a classe do erro e as tentativas
  # ficam, para medir.
  def guardar(attachment, tipo, texto, motivo = {})
    Crm::Ai::ReservaDaMidia.gravar(attachment, dono: @dono) do |atual|
      meta = atual.except(Crm::Ai::FalhaDaMidia::PROXIMA).merge(motivo)
      if texto.present?
        meta = meta.except(Crm::Ai::FalhaDaMidia::FALHA, Crm::Ai::FalhaDaMidia::RELEITURAS_DO_EXPIRADO).merge(CHAVE[tipo] => texto.to_s)
      end
      meta.merge(MARCA[tipo] => true, 'crm_ai_enriched_at' => Time.current.iso8601)
    end
    true
  end
end

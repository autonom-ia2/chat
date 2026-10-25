# PRÉ-VOO (#1624, épico #1585): 10 minutos antes de um follow-up automático sair fora da janela de 24 h, decide o que o envio
# vai usar e já cria o modelo, para a Meta ter tempo de aprovar antes do horário. Hoje cobre a cobrança (lembrete de Atender
# payment_*) e o retorno combinado (ai_callback).
#   - Cobrança: planeja o tipo (cobranca_antes/no_dia/depois) no ponto único (Whatsapp::Templates::EnvioForaDaJanela), criando o
#     modelo quando a conta autorizou e ele não existe.
#   - Retorno: a IA compõe UMA vez, escolhendo entre os modelos aprovados. Se nenhum serve (`no_fitting_template`), planeja o tipo
#     `retorno` já com `ja_recusado: true`, sem repetir a IA. A composição fica gravada: no horário o runner a reusa, sem 2ª chamada
#     paga, se o cliente não respondeu nem a lista de modelos mudou.
# Tudo vai para `metadata['preflight']` (chave do servidor: o cliente não grava nem apaga). Idempotente: uma marca por horário do
# follow-up (iniciada antes do trabalho lento, e também em erro, para não repetir a chamada paga a cada minuto); se o horário
# mudar, a marca antiga deixa de valer e o pré-voo roda de novo. O envio nunca depende dele: sem marca, planeja sem criar.
# Fala com a IA e com a Meta: chamar de job (Crm::FollowUpPreflightJob).
class Crm::FollowUps::Preflight
  ANTECEDENCIA = 10.minutes
  # A composição gravada vale por este tempo e só se o cliente não respondeu depois dela.
  VALIDADE = 15.minutes
  CHAVE = 'preflight'.freeze
  INICIADO = 'iniciado'.freeze
  PRONTO = 'pronto'.freeze
  ERRO = 'erro'.freeze
  Ponto = Whatsapp::Templates::EnvioForaDaJanela

  # O horário do follow-up como a marca o guarda (microssegundos, UTC): a marca só vale para este horário.
  def self.horario(follow_up)
    follow_up.due_at.utc.iso8601(6)
  end

  # A marca pronta para o horário de agora, ou nil (sem marca, com erro, ou de outro horário).
  def self.marca_vigente(follow_up)
    marca = marca_do_horario(follow_up)
    marca if marca && marca['estado'] == PRONTO
  end

  # Precisa rodar: o follow-up tem tipo de modelo e nenhuma marca (nem iniciada, nem com erro) para o horário de agora.
  def self.pendente?(follow_up)
    follow_up.auto_send_message? && !Crm::FollowUps::EnvioForaDaJanela.tipo_de(follow_up).nil? && marca_do_horario(follow_up).nil?
  end

  def self.marca_do_horario(follow_up)
    marca = follow_up.metadata.to_h[CHAVE]
    marca if marca.is_a?(Hash) && marca['due_at'] == horario(follow_up)
  end
  private_class_method :marca_do_horario

  def initialize(follow_up:, now: Time.current)
    @follow_up = follow_up
    @now = now
    @horario = self.class.horario(follow_up)
  end

  def call
    return unless iniciar

    gravar(montar)
  rescue StandardError => e
    # Meta ou IA fora: a marca de erro evita repetir a chamada paga a cada minuto; no horário, o envio planeja sem criar.
    Rails.logger.warn("[crm][preflight] follow_up_id=#{@follow_up.id} #{e.class.name}: #{e.message.to_s[0, 160]}")
    gravar('estado' => ERRO, 'erro' => e.class.name)
  end

  private

  # Sob trava e antes do trabalho lento: confere que ainda vale e grava a marca "iniciado", para um 2º job não repetir.
  def iniciar
    @follow_up.with_lock do
      next false unless @follow_up.pending? && self.class.pendente?(@follow_up)
      next cancelar_do_card_arquivado if card_arquivado?
      next false unless aplica?

      escrever('estado' => INICIADO, 'at' => @now.iso8601)
      true
    end
  end

  # A barreira do arquivamento (#2100), lida com o lembrete travado, como no DueProcessor: um arquivamento em curso
  # termina antes, e o que começar depois espera este lembrete. Sem ela, o SKIP LOCKED da 2ª passagem do
  # Crm::Cards::Archiver pulava o lembrete que o pré-voo segurava, e ele ficava pendente no card arquivado.
  def card_arquivado?
    @follow_up.card_id.present? && Crm::Cards::Archiver.arquivado_sob_trava?(@follow_up.card_id)
  end

  # Cancelado como o arquivamento cancela, sem criar modelo na Meta para um card que não vai mandar nada.
  def cancelar_do_card_arquivado
    @follow_up.update!(status: :canceled, canceled_at: @now,
                       metadata: @follow_up.metadata.to_h.merge('canceled_reason' => Crm::Cards::Archiver::MOTIVO))
    # validar: false, como no #2096: o card arquivado com dono que saiu da conta não passa na validação.
    Crm::FollowUps::CardNextDueUpdater.update(@follow_up.card.reload, validar: false)
    false
  end

  # Fora da janela NO HORÁRIO do envio, no número oficial, com os interruptores ligados e sem barreira do contato.
  def aplica?
    card = @follow_up.card
    conversation = @follow_up.conversation
    return false unless card && conversation && oficial?(conversation) && ligado?(card)
    return false if runner.precondition_fallback_reason

    !Crm::FollowUps::MessagingWindow.new(conversation, at: @follow_up.due_at).can_send_session_message?
  end

  def oficial?(conversation)
    conversation.inbox&.channel_type == Crm::FollowUps::EnvioForaDaJanela::CANAL_OFICIAL
  end

  def ligado?(card)
    return false unless Crm::Ai::Config.enabled?
    return Crm::FollowUps::ServiceReminderScheduler.wanted?(@follow_up, now: @now) if lembrete?

    Crm::Ai::Config.pipeline_callback_enabled?(card.pipeline)
  end

  def montar
    tipo = Crm::FollowUps::EnvioForaDaJanela.tipo_de(@follow_up)
    corpo = lembrete? ? { 'plano' => planejar(tipo, ja_recusado: false) } : retorno(tipo)
    { 'estado' => PRONTO, 'tipo' => tipo }.merge(corpo)
  end

  # Retorno: uma chamada paga de IA; o modelo do tipo só entra quando a IA diz que há o que enviar e nenhum aprovado serve.
  def retorno(tipo)
    composicao, candidatos = runner.compor_antes
    corpo = { 'composicao' => composicao, 'candidatos' => candidatos }
    return corpo unless runner.precisa_do_modelo_do_tipo?(composicao)

    corpo.merge('plano' => planejar(tipo, ja_recusado: true))
  end

  def planejar(tipo, ja_recusado:)
    Ponto.planejar(inbox: @follow_up.conversation.inbox, tipo: tipo, com_valor: @follow_up.card.value_cents.to_i.positive?,
                   ja_recusado: ja_recusado, contato: @follow_up.conversation.contact, criar: true)
  end

  def gravar(corpo)
    @follow_up.with_lock do
      # O follow-up pode ter saído da fila ou mudado de horário durante a chamada lenta: a marca não vale mais.
      next unless @follow_up.pending? && self.class.horario(@follow_up) == @horario

      escrever(corpo.merge('at' => @now.iso8601))
    end
  end

  def escrever(marca)
    @follow_up.update!(metadata: @follow_up.metadata.to_h.merge(CHAVE => marca.merge('due_at' => @horario)))
  end

  def lembrete?
    @follow_up.metadata.to_h['source'] == Crm::FollowUps::ServiceReminderScheduler::SOURCE
  end

  # O runner olha a janela NO HORÁRIO do envio (now: due_at), como o envio vai olhar.
  def runner
    @runner ||= Crm::FollowUps::CallbackRunner.new(follow_up: @follow_up, now: @follow_up.due_at)
  end
end

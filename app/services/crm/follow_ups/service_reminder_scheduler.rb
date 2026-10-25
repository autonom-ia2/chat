# LEMBRETES DE ATENDER (#1498), por data, no mesmo motor do retorno combinado: cada lembrete é um Crm::FollowUp
# auto_send_message (source service_reminder) que o DueProcessor entrega pelo CallbackRunner — a IA escreve a
# mensagem olhando a conversa, escolhe o modelo aprovado fora das 24h e, se não der, vira lembrete para a equipe.
#
# Quando cada um sai (só em funil de Atender, com o interruptor ligado):
#   - progress        o card está há um tempo (4 h a 3 dias, escolhido no funil; 1 dia por padrão) na mesma etapa
#                     sem novidade: avisamos que seguimos cuidando. Um por entrada na etapa; não em "Esperando o
#                     cliente" (a pausa) nem em "Resolvido".
#   - resolved_check  um tempo (1 dia a 1 semana, escolhido no funil; 1 dia por padrão) depois de Resolvido:
#                     perguntamos se deu tudo certo. Mudou o tempo, o lembrete pendente muda de horário.
#   - payment_*       Cobrança: 3 dias antes, no dia e 3 dias depois do vencimento (o depois espera a promessa
#                     de pagamento, se o cliente prometeu um dia mais tarde).
# Sempre no próximo dia e horário liberados do funil (Crm::FollowUps::AllowedSchedule).
# Andamento e "deu certo?" só valem com a conversa aberta para texto (24 h do WhatsApp ou Híbrido pronto): fora dela
# ainda não há modelo para eles (Issue própria, depende do #1518), e um aviso por card na tela da equipe não ajuda.
# Nada para quem recusou mensagem automática, contato com follow-up desligado ou card arquivado.
# Uma mensagem por vez por card (#1589): andamento e "deu certo?" esperam o follow-up automático em curso
# (Crm::FollowUps::UmaMensagemPorVez). O que estava pendente é cancelado e volta a ser criado quando ele termina.
#
# Idempotente: a chave de cada lembrete fica no metadata e não se repete. O que deixou de valer (card fechado,
# mudou de etapa, vencimento mudou, interruptor desligado) é cancelado aqui e conferido de novo no envio (wanted?).
class Crm::FollowUps::ServiceReminderScheduler
  SOURCE = 'service_reminder'.freeze
  # Exigido pelo AutoSendValidator na criação; o texto de verdade a IA escreve no envio.
  MESSAGE_PLACEHOLDER = 'Lembrete do atendimento.'.freeze
  # Passado o horário do "deu certo?", ele ainda sai por este tempo (o horário do funil pode empurrar); depois, não.
  RESOLVED_CHECK_WINDOW = 3.days
  PAYMENT_OFFSETS = { 'payment_before' => -3, 'payment_due' => 0, 'payment_after' => 3 }.freeze
  SEM_PRAZO = %w[espera resolvido].freeze
  Reminder = Struct.new(:kind, :key, :due_at, :after_hours, keyword_init: true)
  # Ao ligar num funil cheio de cards parados, os lembretes novos saem espaçados, não todos no mesmo minuto.
  STAGGER = 2.minutes

  # Lembrete pendente ainda vale? (o DueProcessor pergunta antes de mandar)
  def self.wanted?(follow_up, now: Time.current)
    card = follow_up.card
    return false if card.blank?

    key = follow_up.metadata.to_h['key']
    new(card: card, now: now).desired.any? { |reminder| reminder.key == key }
  end

  # config: { settings:, schedule_config: } que o job calcula uma vez por funil.
  # atraso: espaçamento dos lembretes novos desta rodada. criar: false só cancela o que deixou de valer (o job
  # passou do teto de lembretes novos desta rodada).
  def initialize(card:, now: Time.current, config: {}, atraso: 0, criar: true)
    @card = card
    @now = now
    @criar = criar
    @settings = config[:settings]
    @schedule_config = config[:schedule_config]
    @atraso = atraso
  end

  # -> número de lembretes criados ou levados para outro horário (#1589)
  # Travas na ordem do resto do CRM, lembrete e depois card (#2100, ver Crm::Cards::Archiver): o DueProcessor trava o
  # lembrete e depois lê o card; travar o card antes, aqui, fechava o ciclo (ActiveRecord::Deadlocked).
  # 1. Os lembretes ativos deste card, sem esperar (SKIP LOCKED): o que o DueProcessor segura (na chamada à IA, no envio)
  #    fica com ele, que confere wanted? no envio; não muda de horário nem é cancelado nesta rodada, e não é criado de
  #    novo (create_unless_known! o acha pela chave). Esperar por ele parava o job no card e estourava o statement_timeout.
  # 2. O card, que serializa duas rodadas do job: não criam o mesmo lembrete duas vezes. FOR NO KEY UPDATE: não espera o
  #    FOR KEY SHARE da barreira, que o DueProcessor segura durante a IA e o envio, e ainda espera o arquivamento (FOR
  #    UPDATE) e o UPDATE do card com que o DueProcessor fecha o lembrete (CardNextDueUpdater). Trava a linha sem
  #    recarregar o card (with_lock recarrega e joga fora o que o job pré-carregou); relê só o status do card e o do funil, para não
  #    criar lembrete em card ou funil que acabou de ser arquivado (o arquivamento segura o card até confirmar). O que
  #    mudar até o envio, o DueProcessor confere de novo (wanted?).
  # 3. Com o card travado, nada mais espera: o lembrete que nasceu entre 1 e 2 vem também com SKIP LOCKED.
  def perform
    Crm::Card.transaction do
      @travados = travar_lembretes_livres([])
      next 0 if arquivado_sob_trava?

      @travados += travar_lembretes_livres(@travados)
      wanted = desired
      cancel_obsolete!(wanted.map(&:key))
      @criar ? wanted.count { |reminder| create_unless_known!(reminder) } : 0
    end
  end

  def desired
    return [] if @card.pipeline.blank? || @card.pipeline.counts_as_sale?
    return [] unless sendable_conversation? && destino_aceita_mensagem?

    [*avisos, *payments].compact
  end

  private

  def travar_lembretes_livres(vistos) = known_scope.active.where.not(id: vistos.map(&:id)).order(:id).lock('FOR UPDATE SKIP LOCKED').to_a

  def arquivado_sob_trava?
    status = Crm::Card.where(id: @card.id).lock('FOR NO KEY UPDATE').pick(:status)
    status == 'archived' || Crm::Pipeline.where(id: @card.pipeline_id).pick(:status) == 'archived'
  end

  def settings
    @settings ||= Crm::Ai::Config.service_reminders_settings(@card.pipeline)
  end

  def schedule_config
    @schedule_config ||= Crm::Ai::Config.auto_followup_settings(@card.pipeline)
  end

  def progress
    return unless settings[:progress] && @card.open? && @card.entered_stage_at.present? && texto_livre?
    return if SEM_PRAZO.include?(stage_category) || novidade_recente?

    Reminder.new(kind: 'progress', key: "progress:#{@card.stage_id}:#{@card.entered_stage_at.to_i}",
                 after_hours: progress_after_hours,
                 due_at: schedule_at([@card.entered_stage_at + progress_after_hours.hours, @now].max))
  end

  # "Sem novidade": conversa que andou dentro do tempo escolhido não precisa de aviso.
  def novidade_recente?
    @card.last_activity_at.present? && @card.last_activity_at > @now - progress_after_hours.hours
  end

  def progress_after_hours = settings[:progress_after_hours]

  def resolved_check_after_hours = settings[:resolved_check_after_hours]

  # Andamento e "deu certo?" esperam o follow-up automático que está falando com este cliente (#1589). O pagamento da
  # Cobrança tem dia marcado e não espera.
  def avisos
    return [] unless settings[:progress] || settings[:resolved_check]
    return [] if Crm::FollowUps::UmaMensagemPorVez.new(@card, now: @now).lembrete_espera?

    [progress, resolved_check]
  end

  def resolved_check
    return unless settings[:resolved_check] && @card.resolved? && @card.closed_at.present? && texto_livre?
    return if @card.closed_at < @now - resolved_check_after_hours.hours - RESOLVED_CHECK_WINDOW

    Reminder.new(kind: 'resolved_check', key: "resolved_check:#{@card.closed_at.to_i}",
                 after_hours: resolved_check_after_hours,
                 due_at: schedule_at([@card.closed_at + resolved_check_after_hours.hours, @now].max))
  end

  def payments
    return [] unless settings[:payment] && @card.open? && vencimento.present?

    dias = PAYMENT_OFFSETS.to_h { |kind, offset| [kind, payment_day(kind, offset)] }
    dias.filter_map do |kind, day|
      key = "#{kind}:#{day.iso8601}"
      next unless payment_still_due?(day, key, dias.values)

      inicio_do_dia = zone.local(day.year, day.month, day.day)
      Reminder.new(kind: kind, key: key, due_at: schedule_at([inicio_do_dia, @now].max))
    end
  end

  # Dia que já passou só vale para o lembrete já criado que o horário do funil empurrou (sábado, fora do expediente):
  # conta o due_at do próprio lembrete, não "hoje". E, de dois que caem juntos, só o mais recente sai.
  def payment_still_due?(day, key, todos_os_dias)
    return false if todos_os_dias.any? { |outro| outro > day && outro <= today }

    day >= today || pending_keys.include?(key)
  end

  def pending_keys
    @pending_keys ||= known_scope.active.pluck(Arel.sql("metadata ->> 'key'"))
  end

  # O "depois" espera o dia que o cliente prometeu pagar, quando ele é mais tarde.
  def payment_day(kind, offset)
    day = vencimento + offset
    return day unless kind == 'payment_after' && promessa.present?

    [day, promessa + 1].max
  end

  # O vencimento é um dia (a tela grava "AAAA-MM-DD", que fica 00:00 UTC).
  def vencimento
    @vencimento ||= @card.expected_close_at&.utc&.to_date
  end

  def promessa
    value = @card.metadata.to_h['payment_promise_at']
    @promessa ||= value.present? ? Date.iso8601(value.to_s) : nil
  rescue Date::Error
    nil
  end

  def today
    @today ||= @now.in_time_zone(zone).to_date
  end

  def stage_category
    (@card.stage&.metadata || {})['category']
  end

  # O espaçamento conta a partir do primeiro horário permitido: somado antes, fora do horário (à noite, no sábado) todos
  # caíam juntos na abertura seguinte e saíam de uma vez. A segunda conferência leva quem passou do fim do horário.
  def schedule_at(time)
    horario = Crm::FollowUps::AllowedSchedule.new(config: schedule_config, timezone: timezone)
    horario.next_at(horario.next_at(time) + @atraso)
  end

  def sendable_conversation?
    conversation.present? && messaging_window.whatsapp_capable?
  end

  # As mesmas guardas do envio (CallbackRunner#precondition_fallback_reason), na origem: sem elas, o lembrete era
  # criado, cancelado no envio e criado de novo na rodada seguinte.
  def destino_aceita_mensagem?
    contact = conversation.contact
    !@card.archived? && contact.present? && !contact.opted_out? && !Crm::Ai::Config.contact_followup_disabled?(contact)
  end

  def texto_livre?
    messaging_window.can_send_session_message? || messaging_window.hybrid_web_available?
  end

  def messaging_window
    @messaging_window ||= Crm::FollowUps::MessagingWindow.new(conversation)
  end

  def known_scope
    Crm::FollowUp.where(account_id: @card.account_id, card_id: @card.id).where("metadata ->> 'source' = ?", SOURCE)
  end

  # Só os travados no perform, lidos depois da trava: o DueProcessor pode ter acabado de mandar este mesmo lembrete.
  def cancel_obsolete!(keys)
    @travados.each do |follow_up|
      next if keys.include?(follow_up.metadata.to_h['key'])
      next unless follow_up.pending? || follow_up.overdue?

      follow_up.update!(status: :canceled, canceled_at: @now,
                        metadata: follow_up.metadata.merge('canceled_reason' => 'no_longer_due'))
    end
  end

  # Cancelado não conta: se o lembrete voltar a valer (interruptor religado, vencimento que voltou), é criado de novo.
  def create_unless_known!(reminder)
    known = known_scope.where.not(status: :canceled).find_by("metadata ->> 'key' = ?", reminder.key)
    return reschedule_if_time_changed!(known, reminder) if known

    @card.account.crm_follow_ups.create!(
      card: @card, conversation: conversation, contact: @card.contact, inbox: conversation.inbox,
      title: Crm::FollowUps::ServiceReminderTitle.for(@card.account, reminder.kind),
      due_at: reminder.due_at, timezone: timezone, follow_up_type: :message, automation_mode: :auto_send_message,
      assignee_id: sender&.id, created_by_id: sender&.id,
      metadata: reminder_metadata(reminder)
    )
    true
  end

  def reminder_metadata(reminder)
    { 'source' => SOURCE, 'kind' => reminder.kind, 'key' => reminder.key, 'after_hours' => reminder.after_hours,
      'message_body' => MESSAGE_PLACEHOLDER }.compact
  end

  # #1589: o tempo escolhido mudou e o lembrete ainda não saiu: vai para o novo horário. Lembrete anterior à escolha
  # não tem o tempo gravado e era de 1 dia. Conta como criado: entra no teto e no espaçamento do job (trocar 3 dias
  # por 4 horas não solta todos os pendentes do funil no mesmo minuto).
  # Só o travado no perform: o que outro segura (o DueProcessor mandando) não muda de horário nesta rodada.
  def reschedule_if_time_changed!(known, reminder)
    known = @travados.find { |travado| travado.id == known.id }
    return false if known.nil? || reminder.after_hours.nil? || !known.pending?

    gravado = known.metadata.to_h.fetch('after_hours', Crm::Ai::Config::DEFAULT_SERVICE_REMINDER_HOURS).to_i
    return false if gravado == reminder.after_hours

    known.update!(due_at: reminder.due_at, metadata: known.metadata.merge('after_hours' => reminder.after_hours))
    true
  end

  # Sem quem envie, o auto_send morre em 'sender_required': dono do card, quem atende a conversa ou um admin.
  def sender
    @sender ||= @card.owner || conversation&.assignee || @card.account.administrators.first
  end

  def conversation
    @conversation ||= @card.primary_conversation
  end

  def timezone
    @timezone ||= Crm::Timezone::Resolver.new(contact: @card.contact, account: @card.account).name_or_default
  end

  def zone
    ActiveSupport::TimeZone[timezone] || Time.zone
  end
end

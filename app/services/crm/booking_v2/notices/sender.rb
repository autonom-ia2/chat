# Envia um aviso já tomado pelo cron (`status: sending`) e grava o resultado (#1192, PLANO §2.5).
#
# Ordem, na hora do envio (relida do banco, porque tudo pode ter mudado depois de o aviso ser agendado):
# 1. Flag da conta desligada (kill-switch) → `skipped: 'disabled'`.
# 2. Reunião não está mais marcada → `canceled`; qualquer aviso (também "marcado" e "remarcado" atrasados) de reunião
#    que já começou → `past_due`; lembrete cujo vencimento não bate mais com o início da reunião (reunião mudou de
#    horário sem reprogramar) → `stale`.
# 2b. Reunião que a IA confirmou na própria conversa da caixa de avisos e ali já respondeu (`BookingNotices.already_told?`,
#    #1305) → o "ao marcar" vira `told_in_conversation`, sem repetir a confirmação.
# 3. Parada, nesta precedência: `Contact#opted_out?` → `opted_out`; "Parar avisos" do contato → `stopped`;
#    avisos parados na reunião → `stopped`.
# 4. Página sem caixa de avisos utilizável → `no_inbox`; convite (link de gestão) ausente → `no_invite`.
# 5. Tetos: 4 mensagens automáticas por número em 24 h (`number_cap`) e N por conta em 24 h (`account_cap`,
#    `CRM_BOOKING_NOTICES_ACCOUNT_DAILY_LIMIT`, padrão 300). Contam os avisos que saíram (`sent_at` nas 24 h), os que
#    estão saindo agora (`sending`, de outro processo) e os testes de "Testar no meu WhatsApp". Por número = por
#    contato: o telefone é único por conta (validação do `Contact`). Como o cron marca `sending` ANTES de contar,
#    dois processos ao mesmo tempo se enxergam e o teto nunca é ultrapassado (no limite, os dois podem recusar).
# 6. Regra do canal (`Notices::Route`): janela e modelo aprovado no oficial e no canal API; WAHA manda texto sem janela.
#    WAHA sem conversa: antes de abrir uma, o chat id real vem da WAHA (`Notices::WahaChat`) → `no_whatsapp` ou
#    `waha_unavailable` quando não dá, ou `waha_refused` quando a WAHA recusa o pedido. `no_whatsapp` e `waha_refused`
#    são definitivos. `waha_unavailable` não: a consulta não mandou nada,
#    então o aviso volta para `pending` (marcado em `error_code`), sem chamar o responsável, e o cron tenta de novo
#    até o limite do tipo (`#waha_retry_until`); passado o limite, ou se a reunião começa antes, pula com
#    `waha_unavailable` e avisa o responsável uma vez. `#will_send?` não faz essa consulta (a tela pública não espera
#    a WAHA).
# 7. Envio (`Notices::Delivery`) → `sent` com a mensagem; erro do envio → `failed` com a classe do erro (e o erro vai
#    ao tracker). Falha de entrega posterior do provedor: ver `NoticeDispatchJob` (`delivery_failed`).
#
# Pulado por motivo que exige ação (sem modelo, fora da janela, teto, sem caixa...) ou falha: registra e avisa o
# responsável UMA vez por reunião. Nada aqui altera a reunião (J5-A4).
class Crm::BookingV2::Notices::Sender
  NUMBER_LIMIT = 4
  NUMBER_WINDOW = 24.hours
  ACCOUNT_LIMIT_ENV = 'CRM_BOOKING_NOTICES_ACCOUNT_DAILY_LIMIT'.freeze
  DEFAULT_ACCOUNT_LIMIT = 300
  # Pulos esperados (o cliente parou, a reunião acabou): não chamam o responsável.
  # `told_in_conversation` (#1305): a IA já confirmou a reunião na conversa (`BookingNotices::TOLD_IN_CONVERSATION`).
  QUIET_REASONS = %w[disabled canceled past_due stale opted_out stopped told_in_conversation].freeze
  STALE_TOLERANCE = 1.minute
  WAHA_UNAVAILABLE = 'waha_unavailable'.freeze
  # Até quando vale tentar de novo um aviso que esperou a WAHA (#1270): o "ao marcar" e o "remarcado" ainda servem até
  # 2 h depois do vencimento; o de 1 dia antes, até 6 h antes da reunião; o de 1 hora antes, até o início.
  WAHA_RETRY_AFTER_DUE = 2.hours
  WAHA_RETRY_DAY_BEFORE_MARGIN = 6.hours

  def self.account_limit
    Integer(ENV.fetch(ACCOUNT_LIMIT_ENV, DEFAULT_ACCOUNT_LIMIT).to_s, exception: false) || DEFAULT_ACCOUNT_LIMIT
  end

  # Mensagens automáticas do agendamento para o contato (= o número: telefone é único por conta) nas últimas 24 h:
  # avisos de qualquer reunião dele (`sent_at` fica no aviso mesmo quando remarcar o põe de volta na fila), avisos
  # saindo agora e testes de "Testar no meu WhatsApp". `except`: o aviso que está sendo decidido. Contato ainda não
  # gravado (teste para número novo) não tem nada.
  def self.recent_for_contact(contact, except: nil)
    return 0 if contact.id.nil?

    notices = automatic(Crm::MeetingNotice.joins(meeting: :card).where(crm_cards: { contact_id: contact.id }), except)
    notices.count + recent_tests.where(contact_id: contact.id).count
  end

  def self.recent_for_account(account_id, except: nil)
    automatic(Crm::MeetingNotice.where(account_id: account_id), except).count + recent_tests.where(account_id: account_id).count
  end

  def self.automatic(scope, except)
    scope = scope.where('crm_meeting_notices.sent_at > ? OR crm_meeting_notices.status = ?', NUMBER_WINDOW.ago,
                        Crm::MeetingNotice.statuses[:sending])
    except ? scope.where.not(id: except) : scope
  end

  def self.recent_tests
    Crm::BookingInvite.where("crm_booking_invites.metadata->>'test' = 'true'").where('crm_booking_invites.sent_at > ?', NUMBER_WINDOW.ago)
  end

  private_class_method :automatic, :recent_tests

  # waha_outage: as caixas WAHA que já falharam nesta rodada do cron (`Notices::WahaOutage`).
  def initialize(notice, waha_outage: nil)
    @notice = notice
    @meeting = notice.meeting
    @waha_outage = waha_outage
  end

  def perform
    reason = blocking_reason
    return skip!(waha_gave_up?(reason) ? WAHA_UNAVAILABLE : reason) if reason

    decision = route.decide
    return skip!(decision.reason) unless decision.send?

    waha_problem = waha_chat.prepare if Crm::BookingV2::Notices::WahaChat.needed?(decision, profile.notice_inbox)
    return waha_retry_or_skip!(waha_problem) if waha_problem

    # De novo logo antes de enviar (#1305): a confirmação da IA pode ter sido gravada depois da primeira conferência,
    # com o aviso já em `sending` (fora do alcance do `BookingNotices.mark_told!`).
    told = told_reason
    return skip!(told) if told

    deliver!(decision)
  end

  # Para a tela de sucesso (J2-A6): o aviso "ao marcar" vai sair? Mesma regra, sem enviar nada.
  def will_send?
    blocking_reason.nil? && route.decide.send?
  end

  private

  attr_reader :notice, :meeting, :waha_outage

  def blocking_reason
    meeting_reason || told_reason || stop_reason || setup_reason || cap_reason
  end

  def told_reason
    Crm::BookingV2::BookingNotices::TOLD_IN_CONVERSATION if Crm::BookingV2::BookingNotices.already_told?(notice)
  end

  def meeting_reason
    return 'disabled' unless Crm::Config.booking_v2_enabled?(meeting.account)
    return 'canceled' unless meeting.scheduled?
    return 'past_due' if meeting.starts_at <= Time.current

    'stale' if stale?
  end

  # Defesa: lembrete programado para um horário que a reunião não tem mais.
  def stale?
    return false unless Crm::MeetingNotice::REMINDER_KINDS.include?(notice.kind)

    (notice.due_at - Crm::BookingV2::Notices::Scheduler.expected_due_at(meeting, notice.kind)).abs > STALE_TOLERANCE
  end

  def stop_reason
    return 'opted_out' if contact&.opted_out?
    return 'stopped' if Crm::BookingNoticeStop.stopped?(account_id: meeting.account_id, contact_id: contact&.id)

    'stopped' if meeting.reminders_stopped_at.present?
  end

  def setup_reason
    return 'no_inbox' unless profile&.notices_usable?

    'no_invite' if invite.blank?
  end

  def cap_reason
    return 'number_cap' if self.class.recent_for_contact(contact, except: notice.id) >= NUMBER_LIMIT

    'account_cap' if self.class.recent_for_account(meeting.account_id, except: notice.id) >= self.class.account_limit
  end

  def contact
    meeting.card.contact
  end

  def profile
    @profile ||= Crm::BookingV2::Notices::Scheduler.profile_for(meeting)
  end

  def invite
    @invite ||= Crm::BookingInvite.where(meeting_id: meeting.id).order(:id).last
  end

  def route
    @route ||= Crm::BookingV2::Notices::Route.new(inbox: profile.notice_inbox, contact: contact, conversation: meeting.conversation,
                                                  template: profile.notice_template(notice.kind))
  end

  # WAHA sem conversa: pergunta o chat id antes de abrir uma (`Notices::WahaChat`, #1270).
  def waha_chat
    @waha_chat ||= Crm::BookingV2::Notices::WahaChat.new(inbox: profile.notice_inbox, contact: contact, outage: waha_outage)
  end

  # A consulta à WAHA falhou sem mandar nada: dentro do limite, o aviso volta para a fila sem chamar o responsável.
  def waha_retry_or_skip!(reason)
    return skip!(reason) unless waha_chat.retryable? && Time.current < waha_retry_until

    requeue_waiting_waha!
  end

  # Só devolve o aviso que ainda é o `sending` desta tentativa: se outro processo mexeu nele no meio (o cron o deu por
  # preso, a reunião foi remarcada), vale o que o outro gravou.
  def requeue_waiting_waha!
    Crm::MeetingNotice.where(id: notice.id, status: :sending, attempts: notice.attempts)
                      .update_all(status: Crm::MeetingNotice.statuses[:pending], error_code: WAHA_UNAVAILABLE, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def waha_retry_until
    case notice.kind
    when 'day_before' then meeting.starts_at - WAHA_RETRY_DAY_BEFORE_MARGIN
    when 'hour_before' then meeting.starts_at
    else notice.due_at + WAHA_RETRY_AFTER_DUE
    end
  end

  # A reunião começou enquanto o aviso esperava a WAHA: o motivo que o responsável precisa ver é a WAHA, não o horário.
  def waha_gave_up?(reason)
    reason == 'past_due' && notice.error_code == WAHA_UNAVAILABLE
  end

  def deliver!(decision)
    message = delivery(decision).perform
    notice.update!(status: :sent, sent_at: Time.current, message_id: message.id, skip_reason: nil, error_code: nil)
  rescue StandardError => e
    # Erro do envio (provedor, validação da mensagem, conversa): registrado no aviso, no log e no tracker, e o
    # responsável é avisado; a reunião não muda. Não relança: o cron segue para o próximo aviso.
    Rails.logger.error("CRM booking notice #{notice.id} failed: #{e.class.name}")
    ChatwootExceptionTracker.new(e, account: meeting.account).capture_exception
    notice.update!(status: :failed, error_code: e.class.name.first(255))
    alert!
  end

  def delivery(decision)
    text = Crm::BookingV2::Notices::Text.new(meeting: meeting, invite: invite, kind: notice.kind, page: profile)
    Crm::BookingV2::Notices::Delivery.new(
      decision: decision, inbox: profile.notice_inbox, contact: contact, sender: meeting.created_by,
      content: text.to_s, values: text.template_values, appendix: text.appendix
    )
  end

  # A marca de espera da WAHA (`error_code`) só fica quando é ela o motivo do pulo.
  def skip!(reason)
    waited_waha = notice.error_code == WAHA_UNAVAILABLE && reason != WAHA_UNAVAILABLE
    notice.update!({ status: :skipped, skip_reason: reason }.merge(waited_waha ? { error_code: nil } : {}))
    alert! unless QUIET_REASONS.include?(reason)
  end

  def alert!
    Crm::BookingV2::Notices::AgentAlert.new(meeting, 'notice_failed', { kind: notice.kind, reason: notice.skip_reason || notice.error_code }).perform
  end
end

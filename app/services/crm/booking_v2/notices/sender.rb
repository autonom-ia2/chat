# Envia um aviso já tomado pelo cron (`status: sending`) e grava o resultado (#1192, PLANO §2.5).
#
# Ordem, na hora do envio (relida do banco, porque tudo pode ter mudado depois de o aviso ser agendado):
# 1. Flag da conta desligada (kill-switch) → `skipped: 'disabled'`.
# 2. Reunião não está mais marcada → `canceled`; lembrete de reunião que já começou → `past_due`.
# 3. Parada, nesta precedência: `Contact#opted_out?` → `opted_out`; "Parar avisos" do contato → `stopped`;
#    avisos parados na reunião → `stopped`.
# 4. Página sem caixa de avisos utilizável → `no_inbox`; convite (link de gestão) ausente → `no_invite`.
# 5. Tetos: 4 mensagens automáticas por número em 24 h (`number_cap`) e N por conta em 24 h (`account_cap`,
#    `CRM_BOOKING_NOTICES_ACCOUNT_DAILY_LIMIT`, padrão 300).
# 6. Regra do canal (`Notices::Route`): janela, modelo aprovado, WAHA só com mensagem do cliente em 24 h.
# 7. Envio (`Notices::Delivery`) → `sent` com a mensagem; erro do envio → `failed` com a classe do erro.
#
# Pulado por motivo que exige ação (sem modelo, fora da janela, teto, sem caixa...) ou falha: registra e avisa o
# responsável UMA vez por reunião. Nada aqui altera a reunião (J5-A4).
class Crm::BookingV2::Notices::Sender
  NUMBER_LIMIT = 4
  NUMBER_WINDOW = 24.hours
  ACCOUNT_LIMIT_ENV = 'CRM_BOOKING_NOTICES_ACCOUNT_DAILY_LIMIT'.freeze
  DEFAULT_ACCOUNT_LIMIT = 300
  # Pulos esperados (o cliente parou, a reunião acabou): não chamam o responsável.
  QUIET_REASONS = %w[disabled canceled past_due opted_out stopped].freeze

  def self.account_limit
    Integer(ENV.fetch(ACCOUNT_LIMIT_ENV, DEFAULT_ACCOUNT_LIMIT).to_s, exception: false) || DEFAULT_ACCOUNT_LIMIT
  end

  # Mensagens automáticas do agendamento que saíram para o contato nas últimas 24 h: avisos de qualquer reunião dele
  # (`sent_at` fica no aviso mesmo quando remarcar o põe de volta na fila) e testes de "Testar no meu WhatsApp".
  def self.recent_for_contact(contact)
    since = NUMBER_WINDOW.ago
    notices = Crm::MeetingNotice.joins(meeting: :card).where(crm_cards: { contact_id: contact.id })
                                .where('crm_meeting_notices.sent_at > ?', since).count
    notices + Crm::BookingInvite.where(account_id: contact.account_id, contact_id: contact.id)
                                .where("crm_booking_invites.metadata->>'test' = 'true'").where('sent_at > ?', since).count
  end

  def initialize(notice)
    @notice = notice
    @meeting = notice.meeting
  end

  def perform
    reason = blocking_reason
    return skip!(reason) if reason

    decision = route.decide
    return skip!(decision.reason) unless decision.send?

    deliver!(decision)
  end

  # Para a tela de sucesso (J2-A6): o aviso "ao marcar" vai sair? Mesma regra, sem enviar nada.
  def will_send?
    blocking_reason.nil? && route.decide.send?
  end

  private

  attr_reader :notice, :meeting

  def blocking_reason
    meeting_reason || stop_reason || setup_reason || cap_reason
  end

  def meeting_reason
    return 'disabled' unless Crm::Config.booking_v2_enabled?(meeting.account)
    return 'canceled' unless meeting.scheduled?

    'past_due' if Crm::MeetingNotice::REMINDER_KINDS.include?(notice.kind) && meeting.starts_at <= Time.current
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
    return 'number_cap' if self.class.recent_for_contact(contact) >= NUMBER_LIMIT

    sent_today = Crm::MeetingNotice.where(account_id: meeting.account_id, status: :sent).where('sent_at > ?', 24.hours.ago).count
    'account_cap' if sent_today >= self.class.account_limit
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

  def deliver!(decision)
    message = delivery(decision).perform
    notice.update!(status: :sent, sent_at: Time.current, message_id: message.id, skip_reason: nil, error_code: nil)
  rescue StandardError => e
    # Erro do envio (provedor, validação da mensagem, conversa): registrado no aviso e no log, e o responsável é
    # avisado; a reunião não muda. Não relança: o cron segue para o próximo aviso.
    Rails.logger.error("CRM booking notice #{notice.id} failed: #{e.class.name}")
    notice.update!(status: :failed, error_code: e.class.name.first(255))
    alert!
  end

  def delivery(decision)
    text = Crm::BookingV2::Notices::Text.new(meeting: meeting, invite: invite, kind: notice.kind)
    Crm::BookingV2::Notices::Delivery.new(
      decision: decision, inbox: profile.notice_inbox, contact: contact, sender: meeting.created_by,
      content: text.to_s, values: text.template_values, appendix: text.appendix
    )
  end

  def skip!(reason)
    notice.update!(status: :skipped, skip_reason: reason)
    alert! unless QUIET_REASONS.include?(reason)
  end

  def alert!
    Crm::BookingV2::Notices::AgentAlert.new(meeting, 'notice_failed', { kind: notice.kind, reason: notice.skip_reason || notice.error_code }).perform
  end
end

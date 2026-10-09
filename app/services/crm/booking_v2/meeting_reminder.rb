# "Lembrar" (#1193, J4-A5): com um toque do agente, manda ao cliente, na conversa, uma mensagem curta com o link de
# gestão (`/b/<code>`) pedindo para confirmar o horário. Nunca sai sozinho.
#
# Recusa (MeetingActionError):
# - `not_remindable`: a reunião não veio de uma página de agendamento, não está marcada ou já começou;
# - `already_confirmed`: o cliente já confirmou;
# - `stopped`: o cliente recusou mensagens ativas ou pediu para parar os avisos (contato ou reunião) — nada sai;
# - `no_invite`: a reunião não tem link de gestão;
# - `recently_reminded`: já lembrou há menos de 10 minutos (evita dois toques seguidos);
# - `no_conversation`: nenhuma conversa com o cliente que a pessoa possa ver (o link vai em `url` para copiar);
# - `cannot_reply`: o canal não deixa responder agora, janela fechada (o link vai em `url` para copiar).
#
# A mensagem sai como o próprio agente, texto literal, e fica no card como atividade `booking_agent_reminded`.
class Crm::BookingV2::MeetingReminder
  COOLDOWN = 10.minutes

  def initialize(meeting:, user:, client:)
    @meeting = meeting
    @user = user
    @client = client
  end

  def perform
    validate!
    conversation = reachable_conversation!
    ActiveRecord::Base.transaction do
      # Dois toques ao mesmo tempo: a trava na reunião faz o segundo ver o lembrete do primeiro.
      meeting.lock!
      refuse!('recently_reminded') if recently_reminded?
      message = build_message(conversation).perform
      record!(message)
      message
    end
  end

  private

  attr_reader :meeting, :user, :client

  def validate!
    code = refusal_code
    refuse!(code) if code
  end

  def refusal_code
    return 'not_remindable' unless upcoming_booking?
    return 'already_confirmed' if meeting.confirmation_confirmed?
    return 'stopped' if stopped?

    'no_invite' unless client.invite&.active?
  end

  def upcoming_booking?
    meeting.booking? && meeting.scheduled? && meeting.starts_at > Time.current
  end

  def reachable_conversation!
    conversation = client.reply_conversation
    refuse!('no_conversation', url: client.invite.url) if conversation.blank?
    refuse!('cannot_reply', url: client.invite.url) unless conversation.can_reply?
    conversation
  end

  # Mesma precedência de parada dos avisos automáticos (`Notices::Sender`).
  def stopped?
    contact = client.contact
    return true if contact&.opted_out?
    return true if Crm::BookingNoticeStop.stopped?(account_id: meeting.account_id, contact_id: contact&.id)

    meeting.reminders_stopped_at.present?
  end

  def recently_reminded?
    last = meeting.metadata.to_h['reminded_at']
    last.present? && Time.zone.parse(last.to_s).to_i > COOLDOWN.ago.to_i
  end

  def refuse!(code, url: nil)
    raise Crm::BookingV2::MeetingActionError.new(code, url: url)
  end

  def text
    contact_name = Crm::BookingV2::InviteText.first_name(client.contact)
    I18n.t('crm.booking_v2.remind.text', name: contact_name.empty? ? '' : ", #{contact_name}",
                                         when: Crm::BookingV2::Notices::Text.when_text(meeting), link: client.invite.url,
                                         locale: Crm::BookingV2::Notices::Text.locale(meeting.account))
  end

  def build_message(conversation)
    Autonomia::LiteralMessageBuilder.new(
      user, conversation,
      ActionController::Parameters.new(
        content: text, private: false, message_type: 'outgoing', content_attributes: { crm_booking_invite_id: client.invite.id }
      ),
      literal_content: true
    )
  end

  def record!(message)
    now = Time.current
    meeting.update!(metadata: meeting.metadata.to_h.merge('reminded_at' => now.iso8601, 'reminded_by_id' => user.id))
    Crm::ActivityLogger.new(
      card: meeting.card, actor: user, event_type: 'booking_agent_reminded', conversation: message.conversation,
      payload: { meeting_id: meeting.id, starts_at: meeting.starts_at.iso8601, message_id: message.id, by: 'agent' }
    ).perform
  end
end

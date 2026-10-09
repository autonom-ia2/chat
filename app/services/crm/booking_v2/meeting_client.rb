# O cliente de uma reunião, para o dia da reunião (#1193, J4-A1/A2/A5/A6): número, link do WhatsApp e conversas em
# que o agente pode falar com ele.
#
# Número: o do convidado da reunião (o que o cliente digitou ao marcar, em E.164) ou, sem ele, o do contato. O link do
# WhatsApp é `https://wa.me/<dígitos>`: o E.164 sem o "+" (o número já foi validado ao gravar; aqui não se interpreta
# texto).
#
# Conversas, em ordem: a da reunião (avisos), a do último convite da reunião, a principal do card e as mais recentes
# do contato em caixas de WhatsApp. Só do mesmo contato e da mesma conta. Quem chama filtra pelo que a pessoa pode ver
# (`visible`, a mesma regra de responder uma conversa no painel).
class Crm::BookingV2::MeetingClient
  WHATSAPP_URL = 'https://wa.me/'.freeze
  DIGITS = '0123456789'.chars.freeze
  RECENT_CONVERSATIONS = 5

  # Caixa de WhatsApp: oficial (Cloud/360dialog), canal API de WhatsApp (WAHA ou campanhas) ou Twilio WhatsApp.
  def self.whatsapp_inbox?(inbox)
    return false if inbox.blank?

    Crm::AgentBookingProfile.notice_channel_kind(inbox).present? || inbox.channel.try(:medium).to_s == 'whatsapp'
  end

  def initialize(meeting, visible: ->(_conversation) { true })
    @meeting = meeting
    @visible = visible
  end

  def contact
    meeting.card&.contact
  end

  def phone
    @phone ||= (guest_phone.presence || contact&.phone_number.presence)
  end

  def whatsapp_url
    digits = phone.to_s.delete_prefix('+')
    return if digits.empty? || !digits.chars.all? { |char| DIGITS.include?(char) }

    "#{WHATSAPP_URL}#{digits}"
  end

  # Último convite da reunião: é o link de gestão (`/b/<code>`) que o cliente usa para confirmar, mudar ou cancelar.
  def invite
    return @invite if defined?(@invite)

    @invite = Crm::BookingInvite.where(account_id: meeting.account_id, meeting_id: meeting.id).order(:id).last
  end

  # Primeira conversa que a pessoa vê, para mandar uma mensagem ao cliente (Lembrar, link para remarcar).
  def reply_conversation
    @reply_conversation ||= candidates.find { |conversation| @visible.call(conversation) }
  end

  # Primeira conversa de WhatsApp que a pessoa vê, para o botão "Chamar no WhatsApp".
  def whatsapp_conversation
    @whatsapp_conversation ||= candidates.find { |conversation| self.class.whatsapp_inbox?(conversation.inbox) && @visible.call(conversation) }
  end

  # Para o detalhe da reunião (painel). `conversation_id` é o número da conversa no painel (`display_id`).
  def as_json(*)
    { name: contact&.name, phone: phone, whatsapp_url: whatsapp_url, conversation_id: whatsapp_conversation&.display_id }
  end

  private

  attr_reader :meeting

  def guest_phone
    guests = meeting.meeting_guests
    guest = guests.find { |item| item.contact_guest? && item.phone_number.present? }
    guest&.phone_number
  end

  def candidates
    @candidates ||= begin
      list = [meeting.conversation, invite&.conversation, meeting.card&.primary_conversation]
      list.concat(recent_whatsapp_conversations)
      list.compact.uniq(&:id).select { |conversation| same_client?(conversation) }
    end
  end

  def recent_whatsapp_conversations
    return [] if contact.blank?

    contact.conversations.where(account_id: meeting.account_id).includes(inbox: :channel)
           .order(last_activity_at: :desc, id: :desc).limit(RECENT_CONVERSATIONS)
           .select { |conversation| self.class.whatsapp_inbox?(conversation.inbox) }
  end

  def same_client?(conversation)
    conversation.account_id == meeting.account_id && contact.present? && conversation.contact_id == contact.id
  end
end

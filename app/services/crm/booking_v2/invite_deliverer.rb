# Manda o convite na conversa (#1190, J1-A1/A12) como o próprio usuário, igual a uma resposta digitada. O texto
# é o pronto (`InviteText`) ou o editado pelo agente: até 1000 caracteres, texto puro (sem HTML) e com o link do
# convite dentro. O texto já vem preenchido, então sai literal (`LiteralMessageBuilder`, sem a passada de Liquid).
#
# Quem chama confere que a pessoa pode responder a conversa. ArgumentError 'invite_text_invalid' para texto
# recusado; 'invite_invalid' para convite sem acesso ou conversa de outro contato.
class Crm::BookingV2::InviteDeliverer
  MAX_TEXT = 1000

  def self.plain_text?(text)
    CGI.unescapeHTML(Rails::HTML5::FullSanitizer.new.sanitize(text)) == text
  end

  def initialize(invite:, user:, conversation:, text: nil)
    @invite = invite
    @user = user
    @conversation = conversation
    @text = text
  end

  def perform
    validate!
    ActiveRecord::Base.transaction do
      message = build_message.perform
      invite.update!(sent_at: Time.current, conversation: conversation, channel: 'conversation',
                     metadata: invite.metadata.to_h.merge('delivered_text' => content))
      message
    end
  end

  private

  attr_reader :invite, :user, :conversation

  def validate!
    raise Crm::BookingV2::InviteError, 'invite_invalid' unless invite.active? && same_contact_conversation?

    value = content
    valid = value.length <= MAX_TEXT && value.include?(invite.url) && self.class.plain_text?(value)
    raise Crm::BookingV2::InviteError, 'invite_text_invalid' unless valid
  end

  def same_contact_conversation?
    conversation.present? && conversation.account_id == invite.account_id && conversation.contact_id == invite.contact_id
  end

  def content
    @content ||= (@text.blank? ? Crm::BookingV2::InviteText.new(invite).to_s : @text.to_s).strip
  end

  def build_message
    Autonomia::LiteralMessageBuilder.new(
      user, conversation,
      ActionController::Parameters.new(
        content: content, private: false, message_type: 'outgoing',
        content_attributes: { crm_booking_invite_id: invite.id }
      ),
      literal_content: true
    )
  end
end

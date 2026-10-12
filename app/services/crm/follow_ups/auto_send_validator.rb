class Crm::FollowUps::AutoSendValidator
  def initialize(follow_up)
    @follow_up = follow_up
  end

  def validate
    return unless @follow_up.auto_send_message?

    validate_conversation
    validate_whatsapp_capability
    validate_message_body
    validate_template_fallback
  end

  private

  def validate_conversation
    return if @follow_up.conversation.present?

    @follow_up.errors.add(:conversation, 'is required for auto-send follow-ups')
  end

  def validate_whatsapp_capability
    conversation = @follow_up.conversation
    return if conversation.blank?

    return if Crm::FollowUps::MessagingWindow.new(conversation).whatsapp_capable?

    @follow_up.errors.add(:automation_mode, 'requires a WhatsApp-capable linked conversation')
  end

  def validate_message_body
    return if metadata['message_body'].to_s.strip.present?

    @follow_up.errors.add(:metadata, 'message_body is required for auto-send follow-ups')
  end

  def validate_template_fallback
    conversation = @follow_up.conversation
    return if conversation.blank?
    # AI follow-ups pick + write the template at send time (the runner resolves it
    # via Crm::FollowUps::TemplateCandidates and fills metadata just before
    # MessageSender), so the template is unknowable at create time. Skip the
    # create-time fallback gate for them; the message_body placeholder still guards.
    return if ai_driven?
    # Fechar o follow-up (enviado, atrasado, cancelado) não reabre a pergunta do modelo: se o Híbrido caiu entre o
    # agendamento e o envio, a falha precisa ser gravada em vez de a validação derrubar o update e travar a fila.
    return if @follow_up.status_changed? && !@follow_up.pending?
    return if team_template_fallback_satisfied?(conversation)

    @follow_up.errors.add(:metadata, 'template fallback is required outside the messaging window')
  end

  def team_template_fallback_satisfied?(conversation)
    window = Crm::FollowUps::MessagingWindow.new(conversation, at: @follow_up.due_at)
    return true unless window.requires_template?
    return true if template_fallback_configured?(conversation)

    # Sem modelo, o texto escrito pela equipe sai pelo WhatsApp API do Híbrido (chat#1349). Nada no metadata do
    # cliente decide isso: o MessageSender refaz a pergunta no envio, com o Híbrido do momento.
    window.hybrid_web_available?
  end

  def template_fallback_configured?(conversation)
    inbox = conversation.inbox
    return api_template_configured? if inbox.channel_type == 'Channel::Api'

    native_template_configured?
  end

  def api_template_configured?
    template_id = metadata['whatsapp_api_message_template_id'].presence
    return false if template_id.blank?

    template = @follow_up.account.whatsapp_api_message_templates.active.find_by(id: template_id)
    template.present? && template.inbox_id == @follow_up.conversation.inbox_id
  end

  def native_template_configured?
    metadata['template_name'].to_s.strip.present? && metadata['template_language'].to_s.strip.present?
  end

  def ai_followup?
    metadata['source'] == 'ai_followup'
  end

  # ai_followup OU ai_callback: ambos escolhem template/escrevem o body no envio.
  def ai_driven?
    %w[ai_followup ai_callback].include?(metadata['source'])
  end

  def metadata
    @metadata ||= (@follow_up.metadata || {}).to_h.stringify_keys
  end
end

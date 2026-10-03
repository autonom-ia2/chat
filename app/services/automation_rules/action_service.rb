class AutomationRules::ActionService < ActionService
  include AutomationRules::CrmActions

  def initialize(rule, account, conversation)
    super(conversation)
    @rule = rule
    @account = account
    Current.executed_by = rule
  end

  # `desde` é o índice da ação em que começar: o Decisor (#858) retoma daqui depois de responder.
  # `message` é a mensagem que disparou a regra, quando há uma — é sobre ela que o Decisor pergunta.
  def perform(desde: 0, message: nil)
    @rule.actions.each_with_index do |action, indice|
      next if indice < desde

      @conversation.reload
      action = action.with_indifferent_access
      # O Decisor não roda aqui: o EventDispatcherJob é de todos os listeners. O passo vai para um job,
      # e os passos seguintes só rodam se ele responder a chave combinada.
      break perguntar_ao_decisor(indice, message) if action[:action_name] == Autonomia::Decisores::PASSO

      begin
        send(action[:action_name], action[:action_params])
      rescue StandardError => e
        ChatwootExceptionTracker.new(e, account: @account).capture_exception
      end
    end
  ensure
    Current.reset
  end

  private

  def perguntar_ao_decisor(indice, message)
    message_id = message&.id || @conversation.messages.incoming.reorder(id: :desc).pick(:id)
    return Rails.logger.info("[autonomia][decisor] regra=#{@rule.id} sem mensagem recebida para perguntar") if message_id.blank?

    Autonomia::Decisores::PerguntarJob.perform_later(@rule.id, @conversation.id, message_id, indice)
  end

  def send_attachment(blob_ids)
    return if conversation_a_tweet?

    return unless @rule.files.attached?

    blobs = ActiveStorage::Blob.where(id: blob_ids)

    return if blobs.blank?

    params = { content: nil, private: false, attachments: blobs }
    Messages::MessageBuilder.new(nil, @conversation, params).perform
  end

  def send_webhook_event(webhook_url)
    payload = @conversation.webhook_data.merge(event: "automation_event.#{@rule.event_name}")
    WebhookJob.perform_later(webhook_url[0], payload)
  end

  def send_message(message)
    return if conversation_a_tweet?

    params = { content: message[0], private: false, content_attributes: { automation_rule_id: @rule.id } }
    Messages::MessageBuilder.new(nil, @conversation, params).perform
  end

  def add_private_note(message)
    return if conversation_a_tweet?

    params = { content: message[0], private: true, content_attributes: { automation_rule_id: @rule.id } }
    Messages::MessageBuilder.new(nil, @conversation.reload, params).perform
  end

  def disable_crm_ai_followup(_params)
    update_contact_crm_ai_followup(disabled: true)
  end

  def enable_crm_ai_followup(_params)
    update_contact_crm_ai_followup(disabled: false)
  end

  # A exclusão mora no contato (vale em todos os funis); planner, runner e retorno por data a leem.
  def update_contact_crm_ai_followup(disabled:)
    contact = @conversation.contact
    return if contact.blank?

    key = Crm::Ai::Config::CONTACT_FOLLOWUP_DISABLED_KEY
    contact.update!(additional_attributes: contact.additional_attributes.to_h.merge(key => disabled))
  end

  def send_email_to_team(params)
    teams = Team.where(id: params[0][:team_ids])

    teams.each do |team|
      break unless @account.within_email_rate_limit?

      TeamNotifications::AutomationNotificationMailer.conversation_creation(@conversation, team, params[0][:message])&.deliver_now
      @account.increment_email_sent_count
    end
  end
end

class AutomationRuleListener < BaseListener
  # Fork (#2600): a mesma régua da Escuta. A marca `auto_reply` da conversa é de quando ela nasceu; na reaberta, quem
  # decide é a última mensagem recebida. Assim o aviso de devolução (DSN) que entra pelo In-Reply-To numa conversa
  # resolvida e a reabre não roda a regra de conversa reaberta, e o cliente que reabre a conversa de um autoresponder roda.
  GATILHO_DA_ESCUTA = { 'conversation_created' => 'conversa.criada', 'conversation_opened' => 'conversa.aberta' }.freeze

  def conversation_updated(event)
    process_conversation_event(event, 'conversation_updated')
  end

  def conversation_created(event)
    process_conversation_event(event, 'conversation_created')
  end

  def conversation_opened(event)
    process_conversation_event(event, 'conversation_opened')
  end

  def conversation_resolved(event)
    process_conversation_event(event, 'conversation_resolved')
  end

  def message_created(event)
    message = event.data[:message]

    return if ignore_message_created_event?(event)

    account = message.try(:account)
    changed_attributes = event.data[:changed_attributes]

    return unless rule_present?('message_created', account)

    rules = current_account_rules('message_created', account)

    rules.each do |rule|
      conditions_match = ::AutomationRules::ConditionsFilterService.new(rule, message.conversation,
                                                                        { message: message, changed_attributes: changed_attributes }).perform
      execute_rule(rule, account, message.conversation, message: message) if conditions_match.present?
    end
  end

  private

  def process_conversation_event(event, event_name)
    return if performed_by_automation?(event)
    return if ignore_auto_reply_event?(event, event_name)

    conversation = event.data[:conversation]
    account = conversation.account
    changed_attributes = event.data[:changed_attributes]

    rules = conversation_rules(event_name, account)
    return if rules.blank?

    rules.each do |rule|
      conditions_match = ::AutomationRules::ConditionsFilterService.new(rule, conversation, { changed_attributes: changed_attributes }).perform
      execute_rule(rule, account, conversation) if conditions_match.present?
    end
  end

  # A delayed conversation rule reads as "the conversation has been in this status for N minutes",
  # so a conversation created in that status must arm it too. Creation never dispatches
  # CONVERSATION_UPDATED, and both paths key the episode on the same status_changed_at, so a later
  # update arming the same episode is deduped by the unique index.
  def conversation_rules(event_name, account)
    rules = current_account_rules(event_name, account)
    return rules unless event_name == 'conversation_created'

    rules + current_account_rules('conversation_updated', account).where.not(execution_delay: nil)
  end

  # Delayed rules record a pending execution instead of acting; the sweep re-checks and
  # runs them at due time. Flag off means no arming and no immediate fallback — a delayed
  # message silently becoming instant is worse than skipping.
  def execute_rule(rule, account, conversation, message: nil)
    if rule.execution_delay.present?
      return unless account.feature_enabled?('delayed_automations')

      AutomationRulePendingExecution.schedule(rule: rule, conversation: conversation, message: message)
    else
      ::AutomationRules::ActionService.new(rule, account, conversation).perform(message: message)
    end
  end

  def rule_present?(event_name, account)
    return if account.blank?

    current_account_rules(event_name, account).any?
  end

  def current_account_rules(event_name, account)
    AutomationRule.where(
      event_name: event_name,
      account_id: account.id,
      active: true
    )
  end

  def performed_by_automation?(event)
    event.data[:performed_by].present? && event.data[:performed_by].instance_of?(AutomationRule)
  end

  def ignore_auto_reply_event?(event, event_name)
    return false unless GATILHO_DA_ESCUTA.key?(event_name)

    ::Autonomia::Automacao::Escuta.resposta_automatica?(event.data[:conversation], GATILHO_DA_ESCUTA[event_name], nil)
  end

  def ignore_message_created_event?(event)
    message = event.data[:message]
    performed_by_automation?(event) ||
      message.activity? ||
      message.auto_reply_email? ||
      message.additional_attributes.to_h['whatsapp_api_campaign_id'].present?
  end
end

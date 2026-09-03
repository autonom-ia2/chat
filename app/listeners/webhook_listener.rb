class WebhookListener < BaseListener
  def conversation_status_changed(event)
    conversation = extract_conversation_and_account(event)[0]
    changed_attributes = extract_changed_attributes(event)
    inbox = conversation.inbox
    payload = conversation.webhook_data.merge(event: __method__.to_s, changed_attributes: changed_attributes)
    deliver_webhook_payloads(payload, inbox)
  end

  def conversation_updated(event)
    conversation = extract_conversation_and_account(event)[0]
    changed_attributes = extract_changed_attributes(event)
    inbox = conversation.inbox
    payload = conversation.webhook_data.merge(event: __method__.to_s, changed_attributes: changed_attributes)
    deliver_webhook_payloads(payload, inbox)
  end

  def conversation_created(event)
    conversation = extract_conversation_and_account(event)[0]
    inbox = conversation.inbox
    payload = conversation.webhook_data.merge(event: __method__.to_s)
    deliver_webhook_payloads(payload, inbox)
  end

  def message_created(event)
    message = extract_message_and_account(event)[0]
    inbox = message.inbox

    return unless message.webhook_sendable?

    payload = message.webhook_data.merge(event: __method__.to_s)
    deliver_webhook_payloads(payload, inbox)
  end

  def message_updated(event)
    message = extract_message_and_account(event)[0]
    inbox = message.inbox

    return unless message.webhook_sendable?

    payload = message.webhook_data.merge(event: __method__.to_s)
    deliver_webhook_payloads(payload, inbox)
  end

  def webwidget_triggered(event)
    contact_inbox = event.data[:contact_inbox]
    inbox = contact_inbox.inbox

    payload = contact_inbox.webhook_data.merge(event: __method__.to_s)
    payload[:event_info] = event.data[:event_info]
    deliver_webhook_payloads(payload, inbox)
  end

  def contact_created(event)
    contact, account = extract_contact_and_account(event)
    payload = contact.webhook_data.merge(event: __method__.to_s)
    deliver_account_webhooks(payload, account)
  end

  def contact_updated(event)
    contact, account = extract_contact_and_account(event)
    changed_attributes = extract_changed_attributes(event)
    return if changed_attributes.blank?

    payload = contact.webhook_data.merge(event: __method__.to_s, changed_attributes: changed_attributes)
    deliver_account_webhooks(payload, account)
  end

  def inbox_created(event)
    inbox, account = extract_inbox_and_account(event)
    inbox_webhook_data = Inbox::EventDataPresenter.new(inbox).webhook_data
    payload = inbox_webhook_data.merge(event: __method__.to_s)
    deliver_account_webhooks(payload, account)
  end

  def inbox_updated(event)
    inbox, account = extract_inbox_and_account(event)
    changed_attributes = extract_changed_attributes(event)
    return if changed_attributes.blank?

    inbox_webhook_data = Inbox::EventDataPresenter.new(inbox).webhook_data
    payload = inbox_webhook_data.merge(event: __method__.to_s, changed_attributes: changed_attributes)
    deliver_account_webhooks(payload, account)
  end

  def conversation_typing_on(event)
    handle_typing_status(__method__.to_s, event)
  end

  def conversation_typing_off(event)
    handle_typing_status(__method__.to_s, event)
  end

  # CRM card lifecycle handlers. The method name is the canonical dotted event
  # with dots->underscores (crm.card.won -> crm_card_won), matching
  # Webhook::CRM_WEBHOOK_EVENTS and payload[:event]. Each fans out to subscribing
  # account webhooks via the PII-default-deny builder + retrying delivery job.
  def crm_card_created(event)
    deliver_crm_webhooks(event)
  end

  def crm_card_moved(event)
    deliver_crm_webhooks(event)
  end

  def crm_card_won(event)
    deliver_crm_webhooks(event)
  end

  def crm_card_lost(event)
    deliver_crm_webhooks(event)
  end

  def crm_card_reopened(event)
    deliver_crm_webhooks(event)
  end

  def crm_card_archived(event)
    deliver_crm_webhooks(event)
  end

  private

  # Fan-out for CRM outbound webhooks. The Emitter dispatches IDS ONLY (plan B2);
  # we reload the card by id here. The payload is built PER WEBHOOK because the
  # include_contact_pii opt-in varies between webhooks. Delivery goes through
  # CrmDeliveryJob (bounded retry, :low queue) rather than the core WebhookJob.
  def deliver_crm_webhooks(event)
    event_name = event.data[:event]
    account = Account.find_by(id: event.data[:account_id])
    return if account.blank?

    card = Crm::Card.find_by(id: event.data[:card_id], account_id: account.id)
    return if card.blank?

    account.webhooks.account_type.each do |webhook|
      next unless webhook.subscriptions.to_a.include?(event_name)

      payload = Crm::Webhooks::PayloadBuilder.new(
        card: card,
        event: event_name,
        event_id: event.data[:activity_id],
        changed_attributes: event.data[:changed_attributes],
        include_contact_pii: webhook.include_contact_pii
      ).perform

      Webhooks::CrmDeliveryJob.perform_later(webhook.url, payload,
                                             secret: webhook.secret,
                                             delivery_id: SecureRandom.uuid)
    end
  end

  def handle_typing_status(event_name, event)
    conversation = event.data[:conversation]
    user = event.data[:user]
    inbox = conversation.inbox

    payload = {
      event: event_name,
      user: user.webhook_data,
      conversation: conversation.webhook_data,
      is_private: event.data[:is_private] || false
    }
    deliver_webhook_payloads(payload, inbox)
  end

  def deliver_account_webhooks(payload, account)
    return unless account.api_and_webhooks_enabled?

    account.webhooks.account_type.each do |webhook|
      next unless webhook.subscriptions.include?(payload[:event])

      WebhookJob.perform_later(webhook.url, payload, :account_webhook,
                               secret: webhook.secret,
                               delivery_id: SecureRandom.uuid)
    end
  end

  def deliver_api_inbox_webhooks(payload, inbox)
    return unless inbox.channel_type == 'Channel::Api'
    return if inbox.channel.webhook_url.blank?
    return if autonomia_blocked_api_broadcast_payload?(payload)

    WebhookJob.perform_later(inbox.channel.webhook_url, payload, :api_inbox_webhook,
                             secret: inbox.channel.secret, delivery_id: SecureRandom.uuid)
  end

  def deliver_webhook_payloads(payload, inbox)
    deliver_account_webhooks(payload, inbox.account)
    deliver_api_inbox_webhooks(payload, inbox)
  end

  def autonomia_blocked_api_broadcast_payload?(payload)
    conversation_id = payload.dig(:conversation, :id) || payload.dig('conversation', 'id')
    return false if conversation_id.blank?

    conversation = Conversation.includes(:contact, :contact_inbox).find_by(id: conversation_id)
    return false if conversation.blank?

    ::Autonomia::Channels::BroadcastGuard.blocked_conversation?(conversation)
  end
end

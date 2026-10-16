# Prepend em WebhookListener (chat#1709, fase 3): reação e edição gravadas numa mensagem da caixa WAHA comum
# (Waha::RichNative::Reactions e Edits, pelo painel ou pela volta do conector) NÃO mandam `message_updated` ao webhook
# da caixa. O conector lê todo `message_updated` com `external_error` (nulo ou preenchido) como pedido de reenvio: uma
# reação na mensagem enfileiraria um reenvio (o mapping segura as partes já enviadas, não as que faltam). O pedido ao
# motor é o evento próprio (`c2y_message_reaction` / `c2y_message_edit`, Waha::RichNative::MessageActions); a reação ou
# edição do cliente já veio do motor.
# Só quando a mudança é SÓ isso: colunas `content`, `content_attributes`, `updated_at` e `processed_message_content`,
# e, dentro de `content_attributes`, só `reactions`, `edit_history` e `edited_at` (`content` só muda junto com o
# histórico). Os webhooks da conta, a tela (ActionCable) e o robô seguem recebendo a atualização. Qualquer outra
# mudança (status, apagar, erro de envio) vai ao conector como sempre.
module Waha::RichNative::SilentUpdate
  SILENT_KEYS = %w[reactions edit_history edited_at].freeze
  ALLOWED_COLUMNS = %w[content content_attributes updated_at processed_message_content].freeze

  def self.silent?(previous_changes)
    changes = previous_changes.to_h.stringify_keys
    return false unless changes.key?('content_attributes') && (changes.keys - ALLOWED_COLUMNS).empty?

    changed = changed_attribute_keys(changes['content_attributes'])
    changed.any? && (changed - SILENT_KEYS).empty? && (!changes.key?('content') || changed.include?('edit_history'))
  end

  # As chaves de `content_attributes` cujo valor mudou ([antes, depois] do `previous_changes`).
  def self.changed_attribute_keys(change)
    before, after = Array(change).map { |value| value.to_h.stringify_keys }
    before ||= {}
    after ||= {}
    (before.keys | after.keys).reject { |key| before[key] == after[key] }
  end

  def message_updated(event)
    message = extract_message_and_account(event)[0]
    return super unless waha_silent_update?(message, event.data[:previous_changes])
    return unless message.webhook_sendable?

    deliver_account_webhooks(message.webhook_data.merge(event: 'message_updated'), message.inbox.account)
  end

  private

  def waha_silent_update?(message, previous_changes)
    inbox = message.inbox
    inbox.channel_type == 'Channel::Api' && inbox.channel.try(:waha_provider?) && Waha::RichNative::SilentUpdate.silent?(previous_changes)
  rescue StandardError => e
    Rails.logger.error("[waha] rich native silent update message=#{message.id} #{e.class}")
    false
  end
end

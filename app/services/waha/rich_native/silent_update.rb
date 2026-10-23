# Prepend em WebhookListener (chat#1709, fase 3): reação e edição gravadas numa mensagem da caixa WAHA comum
# (Waha::RichNative::Reactions e Edits, pelo painel ou pela volta do conector) NÃO mandam `message_updated` ao webhook
# da caixa. O conector lê todo `message_updated` com `external_error` (nulo ou preenchido) como pedido de reenvio: uma
# reação na mensagem enfileiraria um reenvio (o mapping segura as partes já enviadas, não as que faltam). O pedido ao
# motor é o evento próprio (`c2y_message_reaction` / `c2y_message_edit`, Waha::RichNative::MessageActions); a reação ou
# edição do cliente já veio do motor.
# Só quando a mudança é SÓ isso: colunas `content`, `content_attributes`, `updated_at` e `processed_message_content`,
# e, dentro de `content_attributes`, só SILENT_KEYS (reação, recibo de leitura, prévia de link, áudio ouvido, apagada
# pelo cliente, voto agregado na enquete, resposta ao evento e edição; `content` só muda junto com o histórico). Os
# webhooks da conta, a tela (ActionCable) e o robô seguem recebendo a atualização. Qualquer outra
# mudança (status, apagar, erro de envio) vai ao conector como sempre. Só com a flag `whatsapp_rich_native` ou a pele
# (`conversa_cara_do_canal`) ligada na conta; com as duas desligadas, igual à main.
module Waha::RichNative::SilentUpdate
  # EXATAMENTE a lista do `ConversaCanal::AtualizacaoDaPele::CHAVES` (#1702, na main): o que a tela grava na "pele" da
  # mensagem e nunca pode chegar ao conector (ele reenvia a mensagem em todo `message_updated` com `external_error`,
  # mesmo nulo). Não delega para `ConversaCanal::AtualizacaoDaPele.so_da_pele?`: ela só aceita `content_attributes` e
  # `updated_at`, e a edição daqui muda também `content` e `processed_message_content` junto com o `edit_history`. O
  # spec confere que as duas listas seguem iguais.
  # `c2y_hidden` e `view_once_resolved_by`: o aviso de visualização única que sai da tela quando a mídia chega
  # (Waha::RichNative::Inbound::ViewOnceResolved). Também na lista do #1702b.
  SILENT_KEYS = %w[reactions read_receipt_sent_at link_preview played_at deleted_by_contact_at poll_votes event_responses
                   edit_history edited_at c2y_hidden view_once_resolved_by].freeze
  ALLOWED_COLUMNS = %w[content content_attributes updated_at processed_message_content].freeze
  # O que a edição (Waha::RichNative::Edits) tira junto com o texto que sai: a tradução dele. Só silencia junto com o
  # `edit_history`; sozinha, a mudança da tradução segue como antes. Fica fora da SILENT_KEYS, que é a lista da pele.
  EDIT_COMPANION_KEYS = %w[translations].freeze

  def self.silent?(previous_changes)
    changes = previous_changes.to_h.stringify_keys
    return false unless changes.key?('content_attributes') && (changes.keys - ALLOWED_COLUMNS).empty?

    changed = changed_attribute_keys(changes['content_attributes'])
    changed -= EDIT_COMPANION_KEYS if changed.include?('edit_history')
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

  # Só com a flag `whatsapp_rich_native` ou a pele (`conversa_cara_do_canal`) na conta, as duas frentes que gravam
  # essas marcas pelo painel; com as duas desligadas, o webhook da caixa recebe tudo, como na main.
  def waha_silent_update?(message, previous_changes)
    inbox = message.inbox
    return false unless inbox.channel_type == 'Channel::Api' && inbox.channel.try(:waha_provider?)
    return false unless Waha::RichNative.enabled?(message.account) || ConversaCanal::Pele.ligada?(message.account)

    Waha::RichNative::SilentUpdate.silent?(previous_changes)
  rescue StandardError => e
    Rails.logger.error("[waha] rich native silent update message=#{message.id} #{e.class}")
    false
  end
end

# `waha_view_once_resolved` (chat#1709, conector c2y-rich-3c): a mídia de uma visualização única chegou depois do aviso
# (Waha::RichNative::Inbound::ViewOnceUnavailable), { id, notice_message_id } (o id do aviso no Chatwoot). Tolerante: a
# mídia desta mensagem ganha `meta.is_view_once` e o aviso, achado por `notice_message_id` (mesma caixa e mesmo
# contato, também noutra conversa) ou, sem ele, pelo `id` entre as últimas mensagens desta conversa, sai da tela
# (`c2y_hidden`) e aponta a mídia (`view_once_resolved_by`). Sem aviso, só a mídia.
# Erro ao esconder o aviso: log com a classe; a mensagem nova é criada assim mesmo.
module Waha::RichNative::Inbound::ViewOnceResolved
  RESOLVED_BY_KEY = 'view_once_resolved_by'.freeze
  LOOKBACK = 50
  MEDIA_TYPES = %w[image audio video file].freeze

  module_function

  def apply(message, data)
    return unless message.incoming? && data.is_a?(Hash)

    attachments = message.attachments.select { |attachment| MEDIA_TYPES.include?(attachment.file_type.to_s) }
    attachments.each { |attachment| attachment.meta = attachment.meta.to_h.merge('is_view_once' => true) }
    notice = notice_by_message_id(message, data['notice_message_id']) || notice_for(message, data['id'].to_s)
    message.instance_variable_set(:@c2y_view_once_notice, notice) if notice
  end

  # Por `notice_message_id`: na MESMA caixa e do MESMO contato, também noutra conversa (a do aviso pode ter sido
  # resolvida e a mídia chegar numa conversa nova). De outro contato ou caixa (id forjado), nada.
  def notice_by_message_id(message, notice_message_id)
    contact_id = message.conversation&.contact_id
    return if notice_message_id.blank? || contact_id.nil?

    notice = Message.joins(:conversation).where(conversations: { contact_id: contact_id })
                    .find_by(id: notice_message_id, inbox_id: message.inbox_id, message_type: :incoming)
    notice if notice && Waha::RichNative::Inbound::ViewOnceUnavailable.notice?(notice)
  end

  def notice_for(message, id)
    return if id.blank? || message.conversation.nil?

    message.conversation.messages.where(inbox_id: message.inbox_id, message_type: :incoming)
           .reorder(id: :desc).limit(LOOKBACK)
           .find { |candidate| candidate.content_attributes.to_h[Waha::RichNative::Inbound::ViewOnceUnavailable::ID_KEY] == id }
  end

  # after_create_commit de Message: esconde o aviso, apontando a mídia que chegou. Nunca levanta (a mídia já foi gravada).
  def after_commit(message)
    notice = message.instance_variable_get(:@c2y_view_once_notice)
    return if notice.nil?

    message.remove_instance_variable(:@c2y_view_once_notice)
    hidden = { Waha::RichNative::Inbound::HIDDEN_KEY => true, RESOLVED_BY_KEY => message.id }
    notice.content_attributes = notice.content_attributes.to_h.merge(hidden)
    notice.save!(validate: false)
  rescue StandardError => e
    Rails.logger.error("[waha] rich native view once resolved message=#{message.id} #{e.class}")
  end
end

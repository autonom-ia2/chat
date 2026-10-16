# Callback `before_create` de Message (chat#1709, fase 2): a escolha do cliente numa lista nativa da caixa WAHA comum.
# O conector customizado cria a mensagem RECEBIDA com `content_attributes.waha_list_reply = { row_id, title }`. Aqui
# isso vira o formato que o resto já lê (o mesmo da oficial, chat#1473):
# - `selected_option = { id, title }`, com o id ORIGINAL da opção (o `row_id` sem a referência "|<id da mensagem>",
#   separado pelo último "|", sem regex; Waha::RichNative.split_row_id);
# - `in_reply_to` = a mensagem da referência, só se o conector não o preencheu e se ela é lista nativa da MESMA
#   conversa e da MESMA caixa, com essa opção;
# - a chave `waha_list_reply` sai.
# Só em mensagem recebida de caixa WAHA comum; nas outras a chave nem chega (Waha::RichNative::ForgeryGuard). Nunca
# interrompe a criação.
class Waha::RichNative::ListReply
  KEY = 'waha_list_reply'.freeze

  def self.before_create(message)
    reply = message.content_attributes.to_h[KEY]
    return if reply.nil?

    attributes = message.content_attributes.to_h.except(KEY)
    attributes = attributes.merge(converted(message, reply, attributes)) if convertible?(message, reply)
    message.content_attributes = attributes
  rescue StandardError => e
    Rails.logger.error("[waha] rich native list reply #{e.class}")
  end

  def self.convertible?(message, reply)
    message.incoming? && reply.is_a?(Hash) && reply['row_id'].present? && message.inbox&.channel.try(:waha_provider?)
  end

  def self.converted(message, reply, attributes)
    option_id, reference = Waha::RichNative.split_row_id(reply['row_id'].to_s)
    changes = { 'selected_option' => { 'id' => option_id, 'title' => reply['title'].presence }.compact }
    return changes if attributes['in_reply_to'].present? || reference.nil?

    target = offered_list(message, reference, option_id)
    target ? changes.merge('in_reply_to' => target.id, 'in_reply_to_external_id' => target.source_id) : changes
  end

  # A lista nativa citada, na MESMA conversa e caixa, com a opção tocada; nil quando não confere.
  def self.offered_list(message, reference, option_id)
    target = Message.find_by(id: reference, conversation_id: message.conversation_id, inbox_id: message.inbox_id,
                             message_type: :outgoing)
    target if target && Waha::RichNative.native_options?(target) && Waha::RichNative.option_ids(target).include?(option_id)
  end
end

# Callback `before_create` de Message (chat#1709, fase 2): a escolha do cliente numa lista nativa da caixa WAHA comum.
# O conector customizado cria a mensagem RECEBIDA com `content_attributes.waha_list_reply = { row_id, title }` (em
# toda caixa, com ou sem a flag).
# - Flag `whatsapp_rich_native` DESLIGADA na conta: nada aqui toca na chave; ela fica como o conector mandou, igual à
#   main.
# - Flag LIGADA: a chave sai (inclusive em erro). Ela só vira escolha quando existe, na MESMA conversa e caixa, uma
#   lista NATIVA nossa que ofereceu exatamente essa opção:
#   - `row_id` com referência ("<opção>|<id da mensagem>", separado pelo último "|", sem regex): confere a lista citada;
#   - sem referência: a última lista nativa da conversa com esse id de opção (nas 50 últimas mensagens nossas). Uma
#     escolha forjada, portanto, só pode apontar uma opção que nós mesmos oferecemos nessas listas (aceito).
#   Com a lista conferida: `selected_option = { id original da opção, title }` e `in_reply_to` = a lista (se o conector
#   não o preencheu; `in_reply_to_external_id` só com o id físico, nunca o provisório `waha-native-pending-`). Sem
#   lista que confira (forja, lista de outra conversa): a mensagem fica como texto comum.
# A trava contra forja na API (Waha::RichNative::ForgeryGuard) vale sempre, com ou sem a flag. Nunca interrompe a criação.
class Waha::RichNative::ListReply
  KEY = 'waha_list_reply'.freeze

  def self.before_create(message)
    return unless handles?(message)

    reply = message.content_attributes.to_h[KEY]
    attributes = message.content_attributes.to_h.except(KEY)
    attributes = attributes.merge(converted(message, reply, attributes)) if convertible?(message, reply)
    message.content_attributes = attributes
  rescue StandardError => e
    Rails.logger.error("[waha] rich native list reply #{e.class}")
    message.content_attributes = message.content_attributes.to_h.except(KEY)
  end

  # A chave veio e a conta tem a flag. Erro ao ler a flag: não toca na mensagem.
  def self.handles?(message)
    message.content_attributes.to_h.key?(KEY) && Waha::RichNative.enabled?(message.account)
  rescue StandardError => e
    Rails.logger.error("[waha] rich native list reply flag #{e.class}")
    false
  end

  def self.convertible?(message, reply)
    message.incoming? && reply.is_a?(Hash) && reply['row_id'].present? && message.inbox&.channel.try(:waha_provider?)
  end

  # As chaves a gravar: vazio quando nenhuma lista nativa confere.
  def self.converted(message, reply, attributes)
    option_id, reference = Waha::RichNative.split_row_id(reply['row_id'].to_s)
    list = offered_list(message, reference, option_id)
    return {} if list.nil?

    changes = { 'selected_option' => { 'id' => option_id, 'title' => reply['title'].presence }.compact }
    return changes if attributes['in_reply_to'].present?

    changes['in_reply_to'] = list.id
    changes['in_reply_to_external_id'] = list.source_id unless pending_source_id?(list.source_id)
    changes
  end

  # A lista nativa nossa que ofereceu a opção, na MESMA conversa e caixa; nil quando nenhuma confere.
  def self.offered_list(message, reference, option_id)
    return Waha::RichNative.latest_native_list(message.conversation, option_id) if reference.nil?

    list = Message.find_by(id: reference, conversation_id: message.conversation_id, inbox_id: message.inbox_id,
                           message_type: :outgoing)
    list if list && Waha::RichNative.native_options?(list) && Waha::RichNative.option_ids(list).include?(option_id)
  end

  def self.pending_source_id?(source_id)
    source_id.blank? || source_id.start_with?(Waha::RichNative::PENDING_PREFIX)
  end
end

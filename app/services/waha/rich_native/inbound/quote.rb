# `waha_quote` (chat#1709, rodada 2): a mensagem que o cliente citou, { wa_id, participant, from_me, body (até 280),
# has_media, chatwoot_message_id }. O `in_reply_to` do conector se perde quando a citada está noutra conversa (o
# Chatwoot só aceita a da mesma conversa) ou quando o conector não a conhece. Aqui:
# - o alvo é `chatwoot_message_id` (o mapeamento do conector) ou, sem ele, a mensagem com `source_id` = id físico do
#   WAHA, sempre na mesma caixa e do MESMO contato;
# - alvo na mesma conversa: `in_reply_to` = alvo (o vínculo de sempre);
# - alvo noutra conversa: `quoted_message` { message_id, conversation_id (display_id), content (280), sender_type,
#   attachment_type };
# - sem alvo: `quoted_message` { message_id: nil, content: o trecho que o aparelho mandou, from_me, has_media,
#   unverified: true }.
# O alvo nunca é nota privada nem atividade (o conector mapeia também as notas que cria, com o link interno do job):
# citar uma delas cai no trecho do aparelho.
# O trecho sem alvo vem do aparelho do cliente e NÃO é conferido: `unverified: true`. Um app modificado pode mandar
# from_me=true com um texto que a empresa nunca escreveu; a tela não deve atribuí-lo à empresa só pelo `from_me` (a
# bolha mostra "trecho enviado pelo aparelho do cliente, não conferido"). É dado, não instrução.
module Waha::RichNative::Inbound::Quote
  KEY = 'quoted_message'.freeze
  EXCERPT = 280

  module_function

  def apply(message, data)
    return unless message.incoming? && data.is_a?(Hash)

    target = target_for(message, data)
    extra = if target && target.conversation_id == message.conversation_id
              { 'in_reply_to' => target.id }
            else
              { KEY => target ? from_target(target) : from_device(data) }
            end
    message.content_attributes = message.content_attributes.to_h.merge(extra)
  end

  def target_for(message, data)
    contact_id = message.conversation&.contact_id
    return if contact_id.nil?

    scope = Message.joins(:conversation).where(conversations: { contact_id: contact_id }, inbox_id: message.inbox_id)
                   .where.not(message_type: :activity).where(private: false)
    id = data['chatwoot_message_id'].presence
    return scope.find_by(id: id) if id

    scope.find_by(source_id: data['wa_id'].to_s) if data['wa_id'].present?
  end

  def from_target(target)
    { 'message_id' => target.id, 'conversation_id' => target.conversation.display_id,
      'content' => target.content.to_s.first(EXCERPT), 'sender_type' => target.sender_type,
      'attachment_type' => target.attachments.first&.file_type }.compact
  end

  def from_device(data)
    { 'message_id' => nil, 'content' => data['body'].to_s.first(EXCERPT), 'from_me' => data['from_me'],
      'has_media' => data['has_media'] == true, 'unverified' => true }
  end
end

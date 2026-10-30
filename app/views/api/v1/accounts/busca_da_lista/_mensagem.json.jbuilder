# #2211 — uma mensagem achada: quem mandou, quando e o texto (o do áudio, quando foi a transcrição que achou).
json.id message.id
json.conversation_id message.conversation.display_id
json.content message.content
json.transcribed_text message.attachments.filter_map { |attachment| attachment.meta&.dig('transcribed_text') }.first
json.created_at message.created_at.to_i
json.message_type message.message_type_before_type_cast
json.private message.private
json.sender_type message.sender_type
json.sender_id message.sender_id
json.sender_name message.sender.try(:available_name) || message.sender.try(:name)
json.contact_name message.conversation.contact&.name
json.inbox_id message.inbox_id

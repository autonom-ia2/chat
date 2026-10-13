json.payload do
  json.array! @contactable_inboxes do |contactable_inbox|
    json.inbox do
      json.partial! 'api/v1/models/inbox_slim', formats: [:json], resource: contactable_inbox[:inbox]
      # fork chat#1457: texto livre na nova conversa quando o WhatsApp Híbrido está pronto
      json.whatsapp_api_start WhatsappHybrid::NewConversation.new(inbox: contactable_inbox[:inbox], contact: @contact).free_text_available?
    end
    json.source_id contactable_inbox[:source_id]
  end
end

json.id message.id
json.content message.content
json.inbox_id message.inbox_id
json.echo_id message.echo_id if message.echo_id
json.conversation_id message.conversation.display_id
json.message_type message.message_type_before_type_cast
json.content_type message.content_type
json.status message.status
json.content_attributes message.content_attributes
# chat#1709: apagar no painel apaga também no WhatsApp do cliente ("Apagar para todos").
json.c2y_revocable Waha::RichNative::Revocable.for(message)
# #1702: qual modelo de WhatsApp a mensagem usou (nome e idioma), para a conversa desenhar os botões dele.
# A jornada de campanha só grava o nome (campaign_template_name): sem idioma, vale o primeiro modelo com esse nome.
# #1717: e a foto do que foi enviado (`enviado`, versão 1); na campanha ela fica em campaign_template_enviado.
# `processed_params` nunca sai daqui.
atributos = message.additional_attributes.is_a?(Hash) ? message.additional_attributes : {}
modelo_usado = atributos['template_params'].is_a?(Hash) ? atributos['template_params'].slice('name', 'language', 'enviado') : {}
if modelo_usado['name'].blank?
  modelo_usado = { 'name' => atributos['campaign_template_name'], 'enviado' => atributos['campaign_template_enviado'] }.compact
end
# #2049: e de qual campanha veio (e com que modelo), para o rótulo do balão mostrar o nome dela também depois de
# recarregar, como já mostra ao vivo pelo websocket.
visiveis = atributos.slice('campaign_id', 'whatsapp_api_campaign_id', 'campaign_template_name').compact
visiveis = visiveis.merge('template_params' => modelo_usado) if modelo_usado['name'].present?
json.additional_attributes(visiveis) if visiveis.present?
json.created_at message.created_at.to_i
json.private message.private
json.source_id message.source_id
json.sender message.sender.push_event_data if message.sender
json.attachments message.attachments.map(&:push_event_data) if message.attachments.present?

json.set! :call, message.call.push_event_data if message.content_type == 'voice_call' && message.respond_to?(:call) && message.call.present?

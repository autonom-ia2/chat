# Motivos de uma mensagem automática não ter saído, gravados em send_error pelo MessageSender. A tela os recebe
# como código (SendErrorCode, #1590): uma fonte só para os dois lados não divergirem.
module Crm::FollowUps::SendFailure
  CONVERSATION_REQUIRED = 'conversation_required'.freeze
  NOT_WHATSAPP_CAPABLE = 'not_whatsapp_capable'.freeze
  SENDER_REQUIRED = 'sender_required'.freeze
  TEMPLATE_NAME_REQUIRED = 'template_name_required'.freeze
  API_TEMPLATE_REQUIRED = 'whatsapp_api_message_template_id is required outside the messaging window'.freeze
  API_TEMPLATE_INVALID = 'whatsapp_api_message_template is invalid for this conversation inbox'.freeze
end

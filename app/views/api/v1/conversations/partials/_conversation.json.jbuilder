# TODO: Move this into models jbuilder
# Currently the file there is used only for search endpoint.
# Everywhere else we use conversation builder in partials folder

json.meta do
  json.sender do
    if conversation.contact.present?
      json.partial! 'api/v1/models/contact', formats: [:json], resource: conversation.contact
    else
      json.additional_attributes({})
      json.availability_status 'offline'
      json.email nil
      json.id conversation.contact_id
      json.name 'Contato removido'
      json.phone_number nil
      json.blocked false
      json.identifier nil
      json.company_id nil if Current.account&.feature_enabled?('companies')
      json.thumbnail nil
      json.custom_attributes({})
    end
  end
  json.channel conversation.inbox.try(:channel_type)
  if conversation.assigned_entity.is_a?(AgentBot)
    json.assignee do
      json.partial! 'api/v1/models/agent_bot_slim', formats: [:json], resource: conversation.assigned_entity
    end
    json.assignee_type 'AgentBot'
  elsif conversation.assignee_type == 'User'
    json.assignee do
      json.partial! 'api/v1/models/agent', formats: [:json], resource: conversation.assigned_entity
    end
    json.assignee_type 'User'
  end
  json.partial! 'enterprise/api/v1/conversations/partials/assignee', conversation: conversation if ChatwootApp.enterprise?
  if conversation.team.present?
    json.team do
      json.partial! 'api/v1/models/team', formats: [:json], resource: conversation.team
    end
  end
  json.hmac_verified conversation.contact_inbox&.hmac_verified
end
# #2067: o agente de IA de onde a conversa veio, para o "Devolver para" (Crm::Passagens::VeioDaIa), só com a flag da conta
# ligada e a conversa com uma pessoa (entra no mesmo meta). As listas passam a página inteira (veio_da_ia), em consultas
# fixas; a conversa lida sozinha consulta a dela. `veio_da_ia: false`: a resposta não leva a chave (marcar como lida/não
# lida), porque null quer dizer "não veio da IA".
if local_assigns[:veio_da_ia] != false && Conversations::FicarAoEnviar.ligado?(conversation.account) &&
   conversation.assignee_type == 'User'
  json.meta { json.veio_da_ia Crm::Passagens::VeioDaIa.da_pagina_ou_de(conversation, local_assigns[:veio_da_ia]) }
end

json.id conversation.display_id
# The dashboard seeds the message thread from this array and then paginates BACKWARD
# by id (before: messages[0].id). Keep the seed as the chronologically latest message,
# but add an id tiebreaker: without it, same-second siblings (e.g. the input_csat survey
# created alongside activity messages during an auto-resolve burst) could resolve to a
# lower-id activity, and backward pagination would then never load the higher-id survey.
last_message = conversation.messages.where(account_id: conversation.account_id)
                           .includes([{ attachments: [{ file_attachment: [:blob] }] }])
                           .reorder(created_at: :desc, id: :desc).first
if last_message.blank?
  json.messages []
else
  json.messages [last_message.try(:push_event_data)]
end

json.account_id conversation.account_id
json.uuid conversation.uuid
json.additional_attributes Crm::AnuncioDeOrigem.atributos_para(Current.user, Current.account_user, conversation.additional_attributes) # #2271
json.agent_last_seen_at conversation.agent_last_seen_at.to_i
json.assignee_last_seen_at conversation.assignee_last_seen_at.to_i
json.can_reply conversation.can_reply?
whatsapp_api_reply = conversation.whatsapp_api_reply? # fork: calculado uma vez para as duas chaves abaixo
json.whatsapp_api_reply whatsapp_api_reply # fork chat#1067: aviso no editor
json.whatsapp_api_rich_native Waha::RichNative.types_for(conversation, api_reply: whatsapp_api_reply) # fork chat#1709: tipos ricos nativos agora
json.whatsapp_api_message_actions Waha::RichNative::WahaInbox.message_actions_for(conversation) # fork chat#1709: reagir/editar
json.whatsapp_api_group Waha::RichNative.api_group?(conversation) # fork chat#1709: conversa de grupo (WAHA e híbrida)
# Temporarily disable this action to avoid message-history lookups during conversation rendering.
json.contact_info_request do
  json.available false
  json.reason nil
  json.delivery_mode nil
end
json.contact_last_seen_at conversation.contact_last_seen_at.to_i
json.custom_attributes conversation.custom_attributes
json.inbox_id conversation.inbox_id
json.labels conversation.cached_label_list_array
json.muted conversation.muted?
json.snoozed_until conversation.snoozed_until
json.status conversation.status
json.created_at conversation.created_at.to_i
json.updated_at conversation.updated_at.to_f
json.timestamp conversation.last_activity_at.to_i
json.first_reply_created_at conversation.first_reply_created_at.to_i
json.unread_count conversation.unread_incoming_messages.count
json.last_non_activity_message conversation.messages.where(account_id: conversation.account_id).non_activity_messages.first.try(:push_event_data)
json.last_activity_at conversation.last_activity_at.to_i
json.priority conversation.priority
json.waiting_since conversation.waiting_since.to_i.to_i
sla_applicable = conversation.account.feature_enabled?('sla') && (!conversation.respond_to?(:sla_applicable?) || conversation.sla_applicable?)
json.sla_policy_id sla_applicable ? conversation.sla_policy_id : nil
json.partial! 'enterprise/api/v1/conversations/partials/conversation', conversation: conversation if ChatwootApp.enterprise?
# Funis da conversa que a pessoa enxerga, para o filtro "Funil" da lista conferir no painel (multifunil #1150), e se há
# card em funil oculto para ela (não é "Sem assunto"). As listas passam a página inteira (crm_funnels), numa consulta só;
# a conversa lida sozinha consulta os dela.
crm_funnel = local_assigns[:crm_funnels]&.[](conversation.id) ||
             Crm::Conversations::PipelineIds.for_current_user([conversation])&.[](conversation.id)
if crm_funnel
  json.crm_pipeline_ids crm_funnel[:ids]
  json.crm_pipeline_hidden crm_funnel[:hidden]
end

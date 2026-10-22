json.meta do
  json.mine_count @conversations_count[:mine_count]
  json.unassigned_count @conversations_count[:unassigned_count]
  json.all_count @conversations_count[:all_count]
end
json.payload do
  crm_funnels = Crm::Conversations::PipelineIds.for_current_user(@conversations)
  veio_da_ia = Conversations::FicarAoEnviar.ligado?(Current.account) ? Crm::Passagens::VeioDaIa.da_lista(@conversations) : nil
  json.array! @conversations do |conversation|
    json.partial! 'api/v1/conversations/partials/conversation',
                  formats: [:json],
                  conversation: conversation,
                  crm_funnels: crm_funnels,
                  veio_da_ia: veio_da_ia
  end
end

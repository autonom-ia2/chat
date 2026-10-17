json.payload do
  crm_funnels = Crm::Conversations::PipelineIds.for_current_user(@conversations)
  json.array! @conversations do |conversation|
    json.partial! 'api/v1/conversations/partials/conversation', formats: [:json], conversation: conversation,
                                                                 crm_funnels: crm_funnels
  end
end

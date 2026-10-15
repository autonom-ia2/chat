json.payload do
  crm_pipeline_ids = Crm::Config.enabled? ? Crm::Conversations::PipelineIds.for(@conversations) : nil
  json.array! @conversations do |conversation|
    json.partial! 'api/v1/conversations/partials/conversation', formats: [:json], conversation: conversation,
                                                                 crm_pipeline_ids: crm_pipeline_ids
  end
end

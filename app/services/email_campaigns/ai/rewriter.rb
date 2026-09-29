class EmailCampaigns::Ai::Rewriter
  SCHEMA = {
    name: 'email_campaign_rewrite',
    schema: {
      type: 'object', properties: { text: { type: 'string' } },
      required: ['text'], additionalProperties: false
    }
  }.freeze

  def initialize(account:, text:, instruction:)
    @account = account
    @text = text
    @instruction = instruction
  end

  def perform
    credential = Crm::Ai::CredentialResolver.new(account: @account).resolve
    response = Crm::Ai::ResponsesClient.new(credential: credential, feature: 'email', account: @account).create(
      model: Crm::Ai::Config::MODEL_FOLLOWUP,
      instructions: EmailCampaigns::Ai::PromptBuilder.rewrite(instruction: @instruction),
      input: @text, schema: SCHEMA
    )
    { text: JSON.parse(response[:text])['text'] }
  end
end

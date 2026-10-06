# Públicos (#992): Jev is never called for real in specs. These helpers turn it on with a fake
# key and capture every request body sent to the (WebMock-stubbed) TypeSafe endpoint.
module AudienceJevHelpers
  JEV_URL = 'https://api.typesafe.ai/v1/systemone'.freeze

  def enable_audience_jev
    allow(CampaignImports::JevConfig).to receive(:enabled?).and_return(true)
    allow(TypesafeAi::Config).to receive_messages(configured?: true, api_key: 'ts_mocked_http', model: 'jev-1.13.0')
  end

  # stub_audience_jev(phone: 'column_1', email: 'none', name: 'column_0', company: 'column_2')
  def stub_audience_jev(confidence: 0.97, schema: 0.99, model: 'jev-1.13.0', **answers)
    requests = []
    stub_request(:post, JEV_URL).to_return do |request|
      requests << JSON.parse(request.body)
      { status: 200, body: audience_jev_body(answers, confidence, schema, model).to_json }
    end
    requests
  end

  def audience_jev_body(answers, confidence, schema, model)
    targets = answers.to_h do |target, choice|
      ["#{target}_column", { type: 'choice', choice: choice, confidence: confidence.is_a?(Hash) ? confidence.fetch(target, 0.97) : confidence }]
    end
    { model: model, answers: targets.merge(schema_valid: { type: 'noul', noul: schema }), usage: { input_tokens: 100, output_tokens: 10 } }
  end

  def create_audience_import(account:, user:, content:, filename: 'publico.csv', content_type: 'text/csv')
    campaign_import = create_campaign_import(account: account, user: user, content: content, filename: filename,
                                             batch_count: 1, content_type: content_type)
    campaign_import.update!(name: 'Clientes', mode: 'single_label', options: { 'flow' => CampaignImport::AUDIENCE_FLOW })
    campaign_import
  end
end

RSpec.configure do |config|
  config.include AudienceJevHelpers
end

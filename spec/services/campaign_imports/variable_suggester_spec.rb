require 'rails_helper'

RSpec.describe CampaignImports::VariableSuggester, :aggregate_failures do
  let(:campaign_import) do
    account, user = create_account_and_user
    import = create_audience_import(
      account: account, user: user,
      content: "Segurado,Fone 1,Corretora,Vencimento\nAna Souza,11987654321,Corretora Alfa,10/2026\n"
    )
    import.update!(schema_resolution: { 'manual_mapping' => { 'name' => 0, 'phone' => 1, 'company' => 2 }, 'header_row' => 1, 'table_index' => 0 })
    CampaignImports::AudienceValidator.new(import).perform
    import.reload
  end
  let(:variables) { [{ 'key' => '1', 'label' => 'nome' }, { 'key' => '2', 'label' => 'mês de vencimento' }] }

  # B1: {{2}} "mês de vencimento" comes suggested as the Vencimento column; Jev sees labels and headers only.
  it 'suggests the column for each variable from labels and headers only' do
    enable_audience_jev
    requests = []
    stub_request(:post, AudienceJevHelpers::JEV_URL).to_return do |request|
      requests << JSON.parse(request.body)
      body = {
        model: 'jev-1.13.0',
        answers: {
          variable_0: { type: 'choice', choice: 'column_0', confidence: 0.93 },
          variable_1: { type: 'choice', choice: 'column_2', confidence: 0.91 }
        }
      }
      { status: 200, body: body.to_json }
    end

    result = described_class.new(campaign_import, variables: variables).perform

    expect(campaign_import.extra_columns).to eq(['Vencimento'])
    expect(result).to eq(
      [{ key: '1', source: { 'source' => 'name' }, confidence: 0.93 },
       { key: '2', source: { 'source' => 'extra', 'column' => 'Vencimento' }, confidence: 0.91 }]
    )
    expect(requests.first.dig('state', 'columns')).to eq(%w[Segurado Corretora Vencimento])
    expect(requests.to_json).not_to include('Ana', 'Souza', '987654321', 'Alfa', '10/2026')
  end

  it 'gives no suggestion when Jev is unsure' do
    enable_audience_jev
    stub_request(:post, AudienceJevHelpers::JEV_URL).to_return(
      status: 200,
      body: { model: 'jev-1.13.0', answers: { variable_0: { type: 'choice', choice: 'column_0', confidence: 0.5 } } }.to_json
    )

    result = described_class.new(campaign_import, variables: variables.first(1)).perform

    expect(result).to eq([{ key: '1', source: nil, confidence: nil }])
  end

  it 'gives no suggestion and makes no request when the journey switch is off' do
    result = described_class.new(campaign_import, variables: variables).perform

    expect(result.pluck(:source)).to eq([nil, nil])
    expect(a_request(:post, AudienceJevHelpers::JEV_URL)).not_to have_been_made
  end

  it 'gives no suggestion when Jev fails' do
    enable_audience_jev
    stub_request(:post, AudienceJevHelpers::JEV_URL).to_return(status: 400, body: '{}')

    expect(described_class.new(campaign_import, variables: variables).perform.pluck(:source)).to eq([nil, nil])
  end
end

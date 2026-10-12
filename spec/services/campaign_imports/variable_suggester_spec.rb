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
    # The audience validation also asks Jev the column types (CampaignImports::ColumnTypes, #1331).
    suggestion = requests.find { |request| request.dig('state', 'task') == described_class::TASK }
    expect(suggestion.dig('state', 'columns')).to eq(%w[Segurado Corretora Vencimento])
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

  # #1331: with the catalog, Jev picks a field the system knows or a column, and the answer is the binding itself.
  describe 'with the field catalog' do
    def catalog_index(key)
      TemplateFields::Catalog.fields.pluck(:key).select { |field| TemplateFields::Catalog.in_audience?(field) }.index(key)
    end

    it 'matches variables to catalog keys and to columns, labels and headers only' do
      campaign_import.account.update!(locale: 'pt_BR')
      enable_audience_jev
      requests = []
      vencimento = catalog_index('minha_empresa.site') + 1
      stub_request(:post, AudienceJevHelpers::JEV_URL).to_return do |request|
        requests << JSON.parse(request.body)
        body = { model: 'jev-1.13.0', answers: {
          variable_0: { type: 'choice', choice: "column_#{catalog_index('cliente.primeiro_nome')}", confidence: 0.94 },
          variable_1: { type: 'choice', choice: "column_#{vencimento}", confidence: 0.9 }
        } }
        { status: 200, body: body.to_json }
      end

      result = described_class.new(campaign_import, variables: variables, catalog: true).perform

      expect(result).to eq(
        [{ key: '1', source: { 'source' => 'field', 'value' => 'cliente.primeiro_nome' }, confidence: 0.94 },
         { key: '2', source: { 'source' => 'field', 'value' => 'publico.Vencimento' }, confidence: 0.9 }]
      )
      columns = requests.find { |request| request.dig('state', 'task') == described_class::CATALOG_TASK }.dig('state', 'columns')
      expect(columns).to include('Primeiro nome do cliente', 'Vencimento')
      expect(columns).not_to include('Nome do negócio', 'Dia e hora do horário')
      expect(requests.to_json).not_to include('Ana', 'Souza', '987654321', 'Alfa', '10/2026')
    end

    it 'gives no suggestion when Jev says nothing fits' do
      enable_audience_jev
      stub_request(:post, AudienceJevHelpers::JEV_URL).to_return(
        status: 200, body: { model: 'jev-1.13.0', answers: { variable_0: { type: 'choice', choice: 'none', confidence: 0.99 } } }.to_json
      )

      expect(described_class.new(campaign_import, variables: variables.first(1), catalog: true).perform)
        .to eq([{ key: '1', source: nil, confidence: nil }])
    end
  end
end

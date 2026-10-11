require 'rails_helper'

# #1331: Jev tells the type of each extra column from the header and the masked format only.
RSpec.describe CampaignImports::ColumnTypes, :aggregate_failures do
  let(:content) do
    "Nome,Celular,Vencimento,Valor,Obs\nAna Souza,11987654321,14/10/2026,\"R$ 1.234,50\",cliente antiga\n"
  end
  let(:reading) do
    parsed = CampaignImports::Parser.new(StringIO.new(content), filename: 'publico.csv').perform
    CampaignImports::SpreadsheetReader.new(parsed, explicit_mapping: { 'name' => 0, 'phone' => 1 }, jev_enabled: false).perform
  end

  def stub_types(answers, model: 'jev-1.13.0', status: 200)
    requests = []
    stub_request(:post, AudienceJevHelpers::JEV_URL).to_return do |request|
      requests << JSON.parse(request.body)
      { status: status, body: { model: model, answers: answers }.to_json }
    end
    requests
  end

  def choice(choice, confidence = 0.95)
    { type: 'choice', choice: choice, confidence: confidence }
  end

  before { enable_audience_jev }

  it 'gives each extra column a catalog type, sending only headers and masked formats' do
    requests = stub_types({ column_0: choice('data'), column_1: choice('moeda'), column_2: choice('texto') })

    expect(described_class.new(reading).perform).to eq('Vencimento' => 'data', 'Valor' => 'moeda', 'Obs' => 'texto')
    expect(requests.first.dig('state', 'columns')).to eq(
      [{ 'header' => 'Vencimento', 'format' => '00/00/0000' }, { 'header' => 'Valor', 'format' => 'Ax 0.000,00' },
       { 'header' => 'Obs', 'format' => 'aaaaaaa aaaaaa' }]
    )
    expect(requests.to_json).not_to include('Ana', '987654321', '14/10/2026', '1.234', 'antiga')
  end

  it 'leaves a column without type when Jev does not know or is unsure' do
    stub_types({ column_0: choice('none'), column_1: choice('moeda', 0.5), column_2: choice('planeta') })

    expect(described_class.new(reading).perform).to eq('Vencimento' => nil, 'Valor' => nil, 'Obs' => nil)
  end

  it 'stores nothing when Jev fails, answers for another model or is off' do
    stub_types({}, status: 500)
    expect(described_class.new(reading).perform).to be_nil

    stub_types({ column_0: choice('data') }, model: 'outro')
    expect(described_class.new(reading).perform).to be_nil

    expect(described_class.new(reading, jev_enabled: false).perform).to be_nil
  end

  it 'reads the stored types of an audience' do
    import = CampaignImport.new(schema_resolution: { 'column_types' => { 'Vencimento' => 'data' } })

    expect(described_class.stored(import)).to eq('Vencimento' => 'data')
    expect(described_class.stored(CampaignImport.new(schema_resolution: {}))).to eq({})
    expect(described_class.stored(nil)).to eq({})
  end

  it 'is stored by the audience validator once the audience is ready' do
    stub_types({ column_0: choice('data'), column_1: choice('moeda'), column_2: choice('none') })
    account, user = create_account_and_user
    import = create_audience_import(account: account, user: user, content: content)
    import.update!(schema_resolution: { 'manual_mapping' => { 'name' => 0, 'phone' => 1 }, 'header_row' => 1, 'table_index' => 0 })

    CampaignImports::AudienceValidator.new(import).perform

    expect(import.reload.schema_resolution['column_types']).to eq('Vencimento' => 'data', 'Valor' => 'moeda', 'Obs' => nil)
  end
end

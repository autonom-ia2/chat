require 'rails_helper'

# "O que fazer hoje" pela IA (#1100, F4a): só números entram, a resposta é conferida, a regra é a reserva.
RSpec.describe Crm::MetaAds::Panel::AiAction do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true' do
      travel_to(Time.zone.parse('2026-10-06T15:00:00-03:00')) { example.run }
    end
  end

  let(:account) { create(:account) }
  let(:connection) { create_meta_ads_insights_connection(account) }
  let(:credential) { { api_key: 'synthetic-test-key', source: :hook } }
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:resolver) { instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: credential) }
  let(:report) do
    {
      days: 7, currency: 'BRL',
      totals: { spend: 1200.0, conversations: 40, quotes: 9, open_quotes: 6, sales: 2, sales_value: 3400.0,
                cost_per_conversation: 30.0, cost_per_sale: 600.0, return_per_real: 2.83 },
      ads: [{ ad_id: '123', name: 'Promo outubro', thumbnail_url: 'https://cdn.example/x.jpg', spend: 700.0, conversations: 25,
              quotes: 6, sales: 2, sales_value: 3400.0, cost_per_sale: 350.0, verdict: 'signal' },
            { ad_id: '456', name: 'Capa', thumbnail_url: nil, spend: 500.0, conversations: 22, quotes: 3, sales: 0,
              sales_value: 0.0, cost_per_sale: nil, verdict: 'review' }],
      confidence: { conversations: 40, ad: 30, ad_name: 8, unknown: 2 },
      action: { kind: 'stalled_quotes', count: 4, value: 6200.0, days: 3, ad_name: 'Promo outubro',
                cards: [{ id: 77, title: 'Maria Souza — cotação', value: 1500.0, conversation_id: 9, waiting_since: 5.days.ago }] }
    }
  end

  before do
    allow(Crm::Ai::CredentialResolver).to receive(:new).with(account: account).and_return(resolver)
    allow(Crm::Ai::ResponsesClient).to receive(:new).with(credential: credential, feature: 'anuncios_meta', account: account).and_return(client)
  end

  def perform
    described_class.new(connection: connection, report: report, language: 'pt_BR').perform
  end

  def answer(**overrides)
    { 'applies' => true, 'kind' => 'stalled_quotes', 'ad_id' => nil, 'headline' => 'Retome as 4 propostas paradas.',
      'body' => 'Mande uma mensagem curta para cada cliente.', 'why' => 'Somam R$ 6.200,00 parados há mais de 3 dias.' }.merge(overrides)
  end

  it 'manda só números, com as ações permitidas, e devolve o texto da IA' do
    expect(client).to receive(:create) do |request|
      expect(request).to include(model: Crm::Ai::Config::MODEL_SUMMARY, schema: described_class::SCHEMA, reasoning_effort: 'medium')
      input = JSON.parse(request[:input])
      expect(input.slice('allowed_kinds', 'confidence')).to eq('allowed_kinds' => %w[stalled_quotes review_ad],
                                                               'confidence' => { 'conversations' => 40, 'ad' => 30, 'ad_name' => 8 })
      expect(input['rule_action']['cards']).to eq([{ 'id' => 77, 'value' => 1500.0, 'waiting_days' => 5 }])
      expect(input['ads'].first.keys).to contain_exactly('ad_id', 'name', 'spend', 'conversations', 'quotes', 'sales', 'cost_per_sale', 'verdict')
      expect(request[:input]).not_to include('Maria Souza')
      { text: answer.to_json }
    end

    expect(perform).to include(source: 'ai', reason: nil, kind: 'stalled_quotes', ad_id: nil, headline: 'Retome as 4 propostas paradas.',
                               days: 7, generated_at: Time.current.iso8601)
  end

  it 'corta os textos nos limites e aceita revisar um anúncio em revisão' do
    allow(client).to receive(:create).and_return(text: answer('kind' => 'review_ad', 'ad_id' => '456', 'headline' => 'a' * 200).to_json)

    result = perform

    expect(result).to include(kind: 'review_ad', ad_id: '456')
    expect(result[:headline].length).to eq(120)
  end

  it '"não se aplica" fica com a regra' do
    allow(client).to receive(:create).and_return(text: answer('applies' => false).to_json)

    expect(perform).to include(source: 'rule', reason: 'not_applicable', kind: 'stalled_quotes', headline: nil)
  end

  it 'resposta inválida fica com a regra: ação fora da lista, anúncio que não está em revisão, título vazio ou JSON quebrado' do
    [answer('kind' => 'wait'), answer('kind' => 'review_ad', 'ad_id' => '123'), answer('headline' => ' ')].each do |bad|
      allow(client).to receive(:create).and_return(text: bad.to_json)
      expect(perform).to include(source: 'rule', reason: 'ai_invalid')
    end

    allow(client).to receive(:create).and_return(text: 'não é json')
    expect(perform).to include(source: 'rule', reason: 'ai_invalid')
  end

  it 'falha do provedor fica com a regra e vai para o log, sem trocar de modelo' do
    allow(client).to receive(:create).once.and_raise(Crm::Ai::ResponsesClient::Error, 'model_not_found')
    allow(Rails.logger).to receive(:warn)

    expect(perform).to include(source: 'rule', reason: 'ai_error')
    expect(client).to have_received(:create).once
    expect(Rails.logger).to have_received(:warn).with(include('error=Crm::Ai::ResponsesClient::Error'))
  end

  it 'sem IA ou sem credencial nem chama o provedor' do
    allow(resolver).to receive(:configured?).and_return(false)
    expect(perform).to include(source: 'rule', reason: 'credentials_missing')

    with_modified_env CRM_AI_ENABLED: 'false' do
      expect(perform).to include(source: 'rule', reason: 'ai_unavailable')
    end
    expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
  end

  it 'nada parado e rastreio bom: a lista libera "no caminho certo"' do
    report[:action] = { kind: 'on_track' }
    report[:ads].each { |ad| ad[:verdict] = 'up' }

    expect(described_class.new(connection: connection, report: report, language: 'pt_BR').allowed_kinds).to eq(%w[on_track])
  end

  it 'registra o custo com a feature anuncios_meta, que a Gestão IA mostra como "Anúncios da Meta"' do
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_call_original
    allow(Resolv).to receive(:getaddresses).with('api.openai.com').and_return(['104.18.6.192'])
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return(
      status: 200, headers: { 'Content-Type' => 'application/json' },
      body: { id: 'resp_1', model: Crm::Ai::Config::MODEL_SUMMARY, output_text: answer.to_json,
              usage: { input_tokens: 900, output_tokens: 60 } }.to_json
    )

    expect { perform }.to change(Crm::AiUsageEvent, :count).by(1)

    event = Crm::AiUsageEvent.last
    expect(event).to have_attributes(account_id: account.id, feature: 'anuncios_meta', model: Crm::Ai::Config::MODEL_SUMMARY)
    expect(Crm::Reports::AiUsage.resource_for_feature(event.feature)).to eq('Anúncios da Meta')
  end
end

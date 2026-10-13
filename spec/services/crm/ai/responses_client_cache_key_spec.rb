require 'rails_helper'

# #1367 — quem precisa de um rótulo de medição diferente da chave de cache (o Construtor, com uma feature por
# fase) passa `cache_key:`. Sem ele, a chave é exatamente a de antes: o cliente é compartilhado com o atendimento.
RSpec.describe Crm::Ai::ResponsesClient do
  let(:account) { create(:account) }
  let(:url) { 'https://api.openai.com/v1/responses' }
  let(:payload) { { output_text: 'ok', model: 'gpt-6.1-sol', output: [] }.to_json }
  let(:params) { { model: 'gpt-6.1-sol', instructions: 'instruction', input: 'input' } }

  before do
    allow(Resolv).to receive(:getaddresses).with('api.openai.com').and_return(['104.18.1.1'])
    allow(Crm::Ai::UsageRecorder).to receive(:record)
    stub_request(:post, url).to_return(body: payload, headers: { 'Content-Type' => 'application/json' })
  end

  def sent_cache_key(client)
    client.create(**params)
    body = nil
    expect(WebMock).to(have_requested(:post, url).with { |request| body = JSON.parse(request.body) })
    body['prompt_cache_key']
  end

  it 'keeps feature:account as the key when no cache_key is given' do
    client = described_class.new(credential: { api_key: 'k' }, feature: 'agente_resposta', account: account)

    expect(sent_cache_key(client)).to eq("agente_resposta:#{account.id}")
  end

  it 'keeps the feature-only key for cache_key_scope: :feature when no cache_key is given' do
    client = described_class.new(credential: { api_key: 'k' }, feature: 'classify', account: account, cache_key_scope: :feature)

    expect(sent_cache_key(client)).to eq('classify')
  end

  it 'uses the explicit cache_key and still records usage under the feature' do
    client = described_class.new(credential: { api_key: 'k' }, feature: 'agente_builder_coleta', account: account,
                                 cache_key: "agente_builder:#{account.id}")

    expect(sent_cache_key(client)).to eq("agente_builder:#{account.id}")
    expect(Crm::Ai::UsageRecorder).to have_received(:record).with(hash_including(feature: 'agente_builder_coleta'))
  end
end

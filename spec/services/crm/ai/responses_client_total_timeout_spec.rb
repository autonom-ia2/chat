require 'rails_helper'

# #2696 — `total_timeout:` envolve só a ida HTTP: estourou, sai o erro de prazo da rede e o registro de uso nem é
# chamado (nenhuma escrita no banco dentro do Timeout). nil, o padrão, não muda nada.
RSpec.describe Crm::Ai::ResponsesClient do
  let(:account) { create(:account) }
  let(:url) { 'https://api.openai.com/v1/responses' }
  let(:params) { { model: 'gpt-6-luna', instructions: 'instruction', input: 'input' } }
  let(:client) { described_class.new(credential: { api_key: 'k' }, feature: 'prospeccao_frase', account: account, max_retries: 0) }
  let(:payload) { { output_text: 'ok', output: [], usage: { input_tokens: 1, output_tokens: 1 } }.to_json }

  before do
    allow(Resolv).to receive(:getaddresses).with('api.openai.com').and_return(['104.18.1.1'])
    allow(Crm::Ai::UsageRecorder).to receive(:record)
  end

  it 'estouro do total_timeout vira erro de prazo e não chama o registro de uso' do
    stub_request(:post, url).to_return do
      sleep 1
      { body: payload, headers: { 'Content-Type' => 'application/json' } }
    end

    expect { client.create(**params, total_timeout: 0.05) }.to raise_error(described_class::Error) do |error|
      expect(error.message).to eq('network_timeout: total_timeout')
      expect(error).to be_tempo_esgotado
      expect(error).to be_passageira
    end
    expect(Crm::Ai::UsageRecorder).not_to have_received(:record)
  end

  # O Timeout que sobra é o teto de cada tentativa (#2579), em volta só do HTTParty.
  it 'sem total_timeout, nada muda: sem o prazo total em volta e o uso é registrado' do
    stub_request(:post, url).to_return(body: payload, headers: { 'Content-Type' => 'application/json' })
    allow(Timeout).to receive(:timeout).and_call_original

    expect(client.create(**params)[:text]).to eq('ok')
    expect(Timeout).not_to have_received(:timeout).with(anything, described_class::TotalTimeout)
    expect(Timeout).to have_received(:timeout).with(described_class::REQUEST_TIMEOUT, described_class::AttemptTimeout).once
    expect(Crm::Ai::UsageRecorder).to have_received(:record).once
  end

  it 'com total_timeout folgado, o uso é registrado fora do prazo' do
    stub_request(:post, url).to_return(body: payload, headers: { 'Content-Type' => 'application/json' })

    expect(client.create(**params, total_timeout: 5)[:text]).to eq('ok')
    expect(Crm::Ai::UsageRecorder).to have_received(:record).once
  end
end

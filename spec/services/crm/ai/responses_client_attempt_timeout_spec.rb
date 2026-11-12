require 'rails_helper'

# #2579 — o `timeout:` do HTTParty vale por fase (abrir, escrever, ler). O cliente faz do mesmo número o teto da
# tentativa inteira: uma abertura lenta seguida de uma leitura lenta, cada uma abaixo do `timeout:`, não somam.
RSpec.describe Crm::Ai::ResponsesClient do
  let(:account) { create(:account) }
  let(:url) { 'https://api.openai.com/v1/responses' }
  let(:params) { { model: 'gpt-6-luna', instructions: 'instruction', input: 'input' } }
  let(:payload) { { output_text: 'ok', output: [], usage: { input_tokens: 1, output_tokens: 1 } }.to_json }

  before do
    allow(Resolv).to receive(:getaddresses).with('api.openai.com').and_return(['104.18.1.1'])
    allow(Crm::Ai::UsageRecorder).to receive(:record)
    stub_request(:post, url).to_return(body: payload, headers: { 'Content-Type' => 'application/json' })
  end

  def segundos_desde(inicio) = Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio

  it 'abertura lenta seguida de leitura lenta: corta no timeout da tentativa, sem somar as fases' do
    client = described_class.new(credential: { api_key: 'k' }, feature: 'automacao_teste', account: account, max_retries: 0)
    allow(HTTParty).to receive(:post).and_wrap_original do |original, *args, **kwargs|
      sleep 0.3 # abrir a conexão, abaixo do timeout
      sleep 0.3 # ler a resposta, também abaixo do timeout
      original.call(*args, **kwargs)
    end
    inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    expect { client.create(**params, timeout: 0.4) }.to raise_error(described_class::Error) do |error|
      expect(error.message).to eq('network_timeout: attempt_timeout')
      expect(error).to be_tempo_esgotado
      expect(error).to be_passageira
    end
    expect(segundos_desde(inicio)).to be < 0.6
    expect(Crm::Ai::UsageRecorder).not_to have_received(:record)
  end

  it 'consulta de DNS lenta do api_base também conta no prazo da tentativa' do
    client = described_class.new(credential: { api_key: 'k' }, max_retries: 0)
    allow(Resolv).to receive(:getaddresses).with('api.openai.com') do
      sleep 1
      ['104.18.1.1']
    end
    allow(HTTParty).to receive(:post).and_call_original
    inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    expect { client.create(**params, timeout: 0.3) }.to raise_error(described_class::Error, 'network_timeout: attempt_timeout')
    expect(segundos_desde(inicio)).to be < 0.6
    expect(HTTParty).not_to have_received(:post)
  end

  it 'a tentativa que estoura entra nas novas tentativas, como os outros prazos da rede' do
    client = described_class.new(credential: { api_key: 'k' })
    allow(client).to receive(:sleep)
    tentativas = 0
    allow(HTTParty).to receive(:post).and_wrap_original do |original, *args, **kwargs|
      tentativas += 1
      sleep 1 if tentativas == 1
      original.call(*args, **kwargs)
    end

    expect(client.create(**params, timeout: 0.2)[:text]).to eq('ok')
    expect(tentativas).to eq(2)
    expect(client).to have_received(:sleep).with(1).once
  end

  it 'dentro do prazo, a resposta volta e o mesmo número segue para o HTTParty' do
    client = described_class.new(credential: { api_key: 'k' }, max_retries: 0)
    allow(HTTParty).to receive(:post).and_call_original

    expect(client.create(**params, timeout: 12)[:text]).to eq('ok')
    expect(HTTParty).to have_received(:post).with(url, hash_including(timeout: 12, max_retries: 0))
  end
end

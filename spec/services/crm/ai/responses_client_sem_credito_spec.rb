require 'rails_helper'

# #3202 — o erro guarda o código que a OpenAI manda no JSON, e `sem_credito?` diz quando a chave ficou sem crédito.
RSpec.describe Crm::Ai::ResponsesClient do
  let(:url) { 'https://api.openai.com/v1/responses' }
  let(:client) { described_class.new(credential: { api_key: 'k' }, max_retries: 0) }
  let(:params) { { model: 'gpt-6-luna', instructions: 'instruction', input: 'oi' } }

  before do
    allow(Resolv).to receive(:getaddresses).with('api.openai.com').and_return(['104.18.1.1'])
    allow(Rails.logger).to receive(:error)
  end

  def respond_with(status, error)
    stub_request(:post, url).to_return(status: status, body: { error: error }.to_json,
                                       headers: { 'Content-Type' => 'application/json' })
  end

  def raised_error
    client.create(**params)
  rescue described_class::Error => e
    e
  end

  it 'marca a chave sem crédito pelo código da OpenAI' do
    respond_with(429, { message: 'You have no credits remaining.', type: 'insufficient_quota', code: 'insufficient_quota' })

    error = raised_error
    expect(error.code).to eq('insufficient_quota')
    expect(error).to be_sem_credito
  end

  it 'usa o tipo quando a OpenAI não manda o código' do
    respond_with(429, { message: 'You have no credits remaining.', type: 'insufficient_quota', code: nil })

    expect(raised_error).to be_sem_credito
  end

  it 'não confunde limite de pedidos com falta de crédito' do
    respond_with(429, { message: 'Rate limit reached', type: 'requests', code: 'rate_limit_exceeded' })

    error = raised_error
    expect(error.code).to eq('rate_limit_exceeded')
    expect(error).not_to be_sem_credito
  end

  it 'erro sem JSON fica sem código' do
    stub_request(:post, url).to_return(status: 502, body: 'Bad gateway')

    error = raised_error
    expect(error.code).to be_nil
    expect(error).not_to be_sem_credito
  end
end

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

  # A resposta real da OpenAI para chave sem crédito, vista no log de produção em 24/11 (#3202): o código é outro, e o
  # tipo é `insufficient_quota`.
  it 'marca sem crédito com a resposta real: code credit_balance_exhausted e type insufficient_quota' do
    respond_with(429, { message: 'You have no credits remaining. Add credits to continue using the API.',
                        type: 'insufficient_quota', code: 'credit_balance_exhausted' })

    error = raised_error
    expect(error.code).to eq('credit_balance_exhausted')
    expect(error.error_type).to eq('insufficient_quota')
    expect(error).to be_sem_credito
  end

  it 'reconhece pelo tipo mesmo com um código que ainda não conhecemos' do
    respond_with(429, { message: 'You have no credits remaining.', type: 'insufficient_quota', code: 'codigo_novo' })

    expect(raised_error).to be_sem_credito
  end

  it 'não repete a chamada quando a chave está sem crédito' do
    respond_with(429, { message: 'You have no credits remaining.', type: 'insufficient_quota', code: 'credit_balance_exhausted' })
    com_novas_tentativas = described_class.new(credential: { api_key: 'k' })
    allow(com_novas_tentativas).to receive(:sleep)

    expect { com_novas_tentativas.create(**params) }.to raise_error(described_class::Error)
    expect(a_request(:post, url)).to have_been_made.once
  end

  it 'continua repetindo o limite de pedidos' do
    respond_with(429, { message: 'Rate limit reached', type: 'requests', code: 'rate_limit_exceeded' })
    com_novas_tentativas = described_class.new(credential: { api_key: 'k' })
    allow(com_novas_tentativas).to receive(:sleep)

    expect { com_novas_tentativas.create(**params) }.to raise_error(described_class::Error)
    expect(a_request(:post, url)).to have_been_made.times(3)
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

require 'rails_helper'

# #2696 — no 4xx a mensagem da OpenAI pode ecoar o input (o texto do cliente): o log grava só error_code e error_type.
# No 5xx a mensagem continua no log.
RSpec.describe Crm::Ai::ResponsesClient do
  let(:url) { 'https://api.openai.com/v1/responses' }
  let(:client) { described_class.new(credential: { api_key: 'k' }, max_retries: 0) }
  let(:params) { { model: 'gpt-6-luna', instructions: 'instruction', input: 'padarias perto da casa da Carla' } }
  let(:logs) { [] }

  before do
    allow(Resolv).to receive(:getaddresses).with('api.openai.com').and_return(['104.18.1.1'])
    allow(Rails.logger).to receive(:error) { |line| logs << line }
  end

  def respond_with(status, message)
    body = { error: { message: message, type: 'invalid_request_error', code: 'invalid_value' } }.to_json
    stub_request(:post, url).to_return(status: status, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  it 'um 400 que ecoa o input não grava o texto no log, só o código e o tipo' do
    respond_with(400, "Invalid input: 'padarias perto da casa da Carla'")

    expect { client.create(**params) }.to raise_error(described_class::Error)
    line = logs.find { |entry| entry.include?('[crm][ai][openai_error]') }
    expect(line).to include('status=400', 'error_code=invalid_value', 'error_type=invalid_request_error')
    expect(line).not_to include('casa da Carla')
  end

  it 'um 500 continua com a mensagem no log' do
    respond_with(500, 'The server had an error while processing your request')

    expect { client.create(**params) }.to raise_error(described_class::Error)
    expect(logs.find { |entry| entry.include?('[crm][ai][openai_error]') }).to include('server had an error')
  end
end

require 'rails_helper'

# #2696 — `max_output_tokens:` é opcional no create: nil (o padrão) não vai no corpo, e os outros chamadores mandam o
# mesmo corpo de antes; com valor, vai como veio.
RSpec.describe Crm::Ai::ResponsesClient do
  let(:url) { 'https://api.openai.com/v1/responses' }
  let(:params) { { model: 'gpt-6-luna', instructions: 'instruction', input: 'input' } }
  let(:client) { described_class.new(credential: { api_key: 'k' }) }

  before do
    allow(Resolv).to receive(:getaddresses).with('api.openai.com').and_return(['104.18.1.1'])
    stub_request(:post, url).to_return(body: { output_text: 'ok', output: [] }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def sent_body
    body = nil
    expect(WebMock).to(have_requested(:post, url).with { |request| body = JSON.parse(request.body) })
    body
  end

  it 'não envia max_output_tokens quando é nil' do
    client.create(**params)

    expect(sent_body).not_to have_key('max_output_tokens')
  end

  it 'envia max_output_tokens quando recebe um valor' do
    client.create(**params, max_output_tokens: 600)

    expect(sent_body['max_output_tokens']).to eq(600)
  end
end

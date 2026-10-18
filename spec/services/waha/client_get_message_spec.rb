require 'rails_helper'

# chat#1489: ler uma mensagem guardada pelo motor, pelo id simples, sem baixar mídia.
RSpec.describe Waha::Client do
  let(:config) { class_double(Waha::Config, api_url: 'https://waha.example', api_key: 'test-key') }
  let(:client) { described_class.new(config: config) }
  let(:url) { 'https://waha.example/api/hybrid-551142155355/chats/5511937016094@c.us/messages/3EB0AAAA?downloadMedia=false' }

  it 'busca a mensagem com a chave no cabeçalho e timeout curto' do
    stub_request(:get, url).with(headers: { 'X-Api-Key' => 'test-key' })
                           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                                      body: { id: 'false_5511937016094@c.us_3EB0AAAA', fromMe: false }.to_json)
    allow(HTTParty).to receive(:get).and_call_original

    result = client.get_message('hybrid-551142155355', '5511937016094@c.us', '3EB0AAAA')

    expect(result).to include('fromMe' => false)
    expect(HTTParty).to have_received(:get).with(url, hash_including(timeout: described_class::GET_MESSAGE_TIMEOUT))
  end

  it 'mensagem que o motor não tem levanta NotFound' do
    stub_request(:get, url).to_return(status: 404, body: '{"message":"not found"}')

    expect { client.get_message('hybrid-551142155355', '5511937016094@c.us', '3EB0AAAA') }.to raise_error(described_class::NotFound)
  end
end

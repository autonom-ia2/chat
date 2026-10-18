require 'rails_helper'

# #1709 × #1702: o pedido direto ao WAHA (reação, lida) vai ao motor que serve a caixa.
describe ConversaCanal::ClienteDoMotor do
  let(:engine) { 'https://wa-autonomia.example' }

  around { |example| with_modified_env(WAHA_RICH_NATIVE_ENGINES: "#{engine}/", WAHA_API_URL: 'https://waha.padrao', WAHA_API_KEY: 'k') { example.run } }

  it 'aponta para o motor listado cujo endereço começa o webhook da caixa' do
    canal = build(:channel_api, webhook_url: "#{engine}/webhooks/chatwoot/s1/1")

    cliente = described_class.para(canal)

    expect(cliente.instance_variable_get(:@base)).to eq(engine)
    expect(cliente.instance_variable_get(:@key)).to eq('k')
  end

  it 'caixa de motor fora da lista: o cliente padrão (WAHA_API_URL)' do
    canal = build(:channel_api, webhook_url: 'https://outro.example/webhooks/chatwoot/s1/1')

    expect(described_class.para(canal).instance_variable_get(:@base)).to eq('https://waha.padrao')
  end
end

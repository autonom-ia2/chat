require 'rails_helper'

# #1709 × #1702: com a flag `whatsapp_rich_native`, o pedido direto ao WAHA (reação, lida) vai ao motor que serve a
# caixa; sem ela, ao motor padrão, como na main.
describe ConversaCanal::ClienteDoMotor do
  let(:engine) { 'https://wa-autonomia.example' }
  let(:canal) { create(:channel_api, webhook_url: "#{engine}/webhooks/chatwoot/s1/1") }

  around do |example|
    with_modified_env(WAHA_RICH_NATIVE_ENGINES: "#{engine}/", WAHA_API_URL: 'https://waha.padrao', WAHA_API_KEY: 'k') { example.run }
  end

  def base_de(cliente)
    cliente.instance_variable_get(:@base)
  end

  context 'with the flag' do
    before { canal.account.enable_features!(Waha::RichNative::FLAG) }

    it 'aponta para o motor listado cujo endereço começa o webhook da caixa, com a mesma chave' do
      cliente = described_class.para(canal)

      expect(base_de(cliente)).to eq(engine)
      expect(cliente.instance_variable_get(:@key)).to eq('k')
    end

    it 'caixa de motor fora da lista: o cliente padrão (WAHA_API_URL)' do
      canal.update!(webhook_url: 'https://outro.example/webhooks/chatwoot/s1/1')

      expect(base_de(described_class.para(canal))).to eq('https://waha.padrao')
    end
  end

  it 'sem a flag: o cliente padrão, mesmo com o motor listado (como na main)' do
    expect(base_de(described_class.para(canal))).to eq('https://waha.padrao')
  end
end

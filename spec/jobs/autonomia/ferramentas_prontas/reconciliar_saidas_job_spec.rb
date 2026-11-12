require 'rails_helper'

# #2942: a reconciliação dos IPs próprios das consultas grátis. Troca o IP que sumiu da Webshare, alerta a fatia vazia ou
# quase, e a Webshare fora. A Webshare é dublada.
RSpec.describe Autonomia::FerramentasProntas::ReconciliarSaidasJob do
  let(:account) { create(:account) }
  let(:registros) { Autonomia::FerramentasProntas::ProxyDaConta }
  let(:fatia) { '203.0.113.11,203.0.113.12,203.0.113.13,203.0.113.14' }

  around do |example|
    with_modified_env(WEBSHARE_LOOKUP_PROXY_ADDRESSES: fatia, WEBSHARE_RESERVED_PROXY_ADDRESSES: fatia) { example.run }
  end

  before do
    zerar_saida_das_prontas
    ligar_ip_proprio(account)
    allow(Rails.logger).to receive(:error).and_call_original
    allow(Rails.logger).to receive(:warn).and_call_original
  end

  def lista(*finais)
    finais.map { |final| proxy_da_webshare(final, "203.0.113.#{final}") }
  end

  it 'troca o IP da conta que sumiu da Webshare e avisa o IP da fatia que sumiu' do
    registros.create!(account: account, proxy_address: '203.0.113.11', proxy_port: 6000, webshare_proxy_id: '11', assigned_at: 1.day.ago)
    webshare_datacenter(lista(12, 13, 14))

    described_class.perform_now

    expect(registros.sole).to have_attributes(proxy_address: '203.0.113.12', webshare_proxy_id: '12')
    expect(Rails.logger).to have_received(:error).with(a_string_including('ip_da_fatia_sumiu', '203.0.x.x'))
  end

  it 'nao troca o IP de conta sem a flag (desligada, tudo sai pelo IP do servidor)' do
    account.disable_features!(Autonomia::FerramentasProntas::Saida::FLAG)
    registros.create!(account: account, proxy_address: '203.0.113.11', proxy_port: 6000, webshare_proxy_id: '11', assigned_at: 1.day.ago)
    webshare_datacenter(lista(12, 13, 14))

    described_class.perform_now

    expect(registros.sole.proxy_address).to eq('203.0.113.11')
  end

  it 'alerta a fatia vazia e a fatia com menos de 3 IPs livres' do
    webshare_datacenter(lista(11, 12))
    registros.create!(account: account, proxy_address: '203.0.113.11', proxy_port: 6000, webshare_proxy_id: '11', assigned_at: Time.current)

    described_class.perform_now
    expect(Rails.logger).to have_received(:warn).with(a_string_including('fatia_quase_vazia', 'só 1 IP'))

    webshare_datacenter(lista(11))
    described_class.perform_now
    expect(Rails.logger).to have_received(:error).with(a_string_including('fatia_vazia'))
  end

  it 'a Webshare fora: alerta e nao mexe em nada' do
    registros.create!(account: account, proxy_address: '203.0.113.11', proxy_port: 6000, webshare_proxy_id: '11', assigned_at: 1.day.ago)
    webshare_datacenter_fora

    described_class.perform_now

    expect(registros.sole.proxy_address).to eq('203.0.113.11')
    expect(Rails.logger).to have_received(:error).with(a_string_including('webshare_indisponivel'))
  end

  it 'stack sem fatia e sem conta com IP: nao pergunta a Webshare' do
    cliente = webshare_datacenter(lista(11))

    with_modified_env(WEBSHARE_LOOKUP_PROXY_ADDRESSES: '') { described_class.perform_now }

    expect(cliente).not_to have_received(:proxies)
  end
end

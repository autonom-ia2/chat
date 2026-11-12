require 'rails_helper'

# #2942: cada conta consulta as fontes grátis por um IP próprio da Webshare. A escolha (fatia E reservada, vivo, fora de
# quarentena e do WhatsApp, um IP por conta), a troca e, sem IP próprio, o IP do servidor com contador (decisão do Rodrigo, 12/11).
RSpec.describe Autonomia::FerramentasProntas::Saida do
  let(:account) { create(:account) }
  let(:outra) { create(:account) }
  let(:primeiro) { proxy_da_webshare(11, '203.0.113.11') }
  let(:segundo) { proxy_da_webshare(12, '203.0.113.12') }
  let(:terceiro) { proxy_da_webshare(13, '203.0.113.13') }
  let(:registros) { Autonomia::FerramentasProntas::ProxyDaConta }

  around do |example|
    with_modified_env(WEBSHARE_LOOKUP_PROXY_ADDRESSES: '203.0.113.11, 203.0.113.12,203.0.113.13',
                      WEBSHARE_RESERVED_PROXY_ADDRESSES: '198.51.100.9,203.0.113.11,203.0.113.12,203.0.113.13') { example.run }
  end

  before do
    zerar_saida_das_prontas
    ligar_ip_proprio(account)
    ligar_ip_proprio(outra)
  end

  def queda_do_dia
    Redis::Alfred.with { |conn| conn.hgetall("#{described_class::CONTADOR}:#{Time.current.utc.to_date.iso8601}") }
  end

  it 'flag desligada (ou sem conta): sai pelo IP do servidor, sem perguntar a Webshare' do
    cliente = webshare_datacenter([primeiro])
    account.disable_features!(described_class::FLAG)

    expect(described_class.para(account.id)).to be_nil
    expect(described_class.para(nil)).to be_nil
    expect(cliente).not_to have_received(:proxies)
    expect(registros.count).to eq(0)
  end

  it 'a 1a consulta da conta ganha um IP da fatia, com a credencial so em memoria; a seguinte reusa o mesmo' do
    webshare_datacenter([primeiro, segundo])

    proxy = described_class.para(account.id)

    expect([proxy.address, proxy.port]).to eq(['203.0.113.11', 6000])
    expect(proxy.http_options).to include(proxy_user: 'user-11', proxy_pass: 'senha-11')
    expect(proxy.inspect).not_to include('senha-11')
    expect(registros.sole).to have_attributes(account_id: account.id, proxy_address: '203.0.113.11', proxy_port: 6000,
                                              webshare_proxy_id: '11')
    expect(described_class.para(account.id).address).to eq('203.0.113.11')
    expect(registros.count).to eq(1)
  end

  it 'duas contas nunca dividem o IP' do
    webshare_datacenter([primeiro, segundo])

    expect([described_class.para(account.id).address, described_class.para(outra.id).address]).to eq(%w[203.0.113.11 203.0.113.12])
  end

  it 'so serve o IP que esta na fatia E na reservada, valido e do Brasil; o da fatia fora da reservada alerta' do
    allow(Rails.logger).to receive(:error).and_call_original
    webshare_datacenter([proxy_da_webshare(9, '198.51.100.9'), proxy_da_webshare(11, '203.0.113.11', valido: false),
                         proxy_da_webshare(12, '203.0.113.12', pais: 'US'), terceiro, proxy_da_webshare(14, '203.0.113.14')])

    with_modified_env(WEBSHARE_LOOKUP_PROXY_ADDRESSES: '203.0.113.11,203.0.113.12,203.0.113.13,203.0.113.14') do
      expect(described_class.para(account.id).address).to eq('203.0.113.13')
      expect(described_class.para(outra.id)).to be_nil
    end
    expect(Rails.logger).to have_received(:error).with(a_string_including('fora_da_reservada', '203.0.x.x'))
  end

  it 'IP que um numero de WhatsApp usa nunca vai para a conta' do
    webshare_datacenter([primeiro, segundo])
    WhatsappProxy::Assignment.create!(account: outra, session_name: 'sessao-teste', pool: 'datacenter', origin: 'assigned',
                                      proxy_address: '203.0.113.11', proxy_port: 6000, webshare_proxy_id: '11',
                                      assigned_at: Time.current)

    expect(described_class.para(account.id).address).to eq('203.0.113.12')
  end

  it 'o IP da conta que foi de molho ou sumiu da Webshare e trocado na consulta seguinte' do
    webshare_datacenter([primeiro, segundo, terceiro])
    described_class.para(account.id)
    Autonomia::FerramentasProntas::ProxyEmQuarentena.por!('203.0.113.11', 'brasilapi.com.br 429')

    expect(described_class.para(account.id).address).to eq('203.0.113.12')

    webshare_datacenter([primeiro, terceiro])
    expect(described_class.para(account.id).address).to eq('203.0.113.13')
    expect(registros.sole).to have_attributes(proxy_address: '203.0.113.13', webshare_proxy_id: '13')
  end

  it 'Webshare fora ou sem IP livre, sai pelo IP do servidor com aviso e o contador do dia' do
    allow(Rails.logger).to receive(:warn).and_call_original
    webshare_datacenter_fora

    expect(described_class.para(account.id)).to be_nil

    webshare_datacenter([primeiro])
    described_class.para(account.id)
    expect(described_class.para(outra.id)).to be_nil
    expect(queda_do_dia).to eq('webshare_indisponivel' => '1', 'nenhum_ip_livre' => '1')
    expect(Rails.logger).to have_received(:warn).with(a_string_including("conta=#{outra.id} motivo=nenhum_ip_livre"))
  end

  it 'a Webshare fora e lembrada por um minuto: a consulta seguinte nao espera o cliente de novo' do
    cliente = webshare_datacenter_fora

    2.times { described_class.para(account.id) }

    expect(cliente).to have_received(:proxies).once
  end

  it 'erro de rede que o cliente da Webshare nao traduz, ou o banco fora: IP do servidor, cada um com o seu motivo' do
    cliente = webshare_datacenter([])
    allow(cliente).to receive(:proxies).and_raise(Errno::ECONNRESET)
    expect(described_class.para(account.id)).to be_nil

    webshare_datacenter([primeiro])
    allow(registros).to receive(:find_by).and_raise(ActiveRecord::ConnectionNotEstablished)
    expect(described_class.para(outra.id)).to be_nil

    expect(queda_do_dia).to eq('webshare_sem_rede' => '1', 'banco_indisponivel' => '1')
  end

  it 'o IP da conta que passou a ser usado por um numero de WhatsApp e trocado na consulta seguinte' do
    allow(Rails.logger).to receive(:error).and_call_original
    webshare_datacenter([primeiro, segundo])
    described_class.para(account.id)
    WhatsappProxy::Assignment.create!(account: outra, session_name: 'sessao-teste', pool: 'datacenter', origin: 'assigned',
                                      proxy_address: '203.0.113.11', proxy_port: 6000, webshare_proxy_id: '11',
                                      assigned_at: Time.current)

    expect(described_class.para(account.id).address).to eq('203.0.113.12')
    expect(Rails.logger).to have_received(:error).with(a_string_including('ip_no_whatsapp'))
  end

  it 'a conferencia da fatia contra a reservada roda uma vez por escolha, nao uma por proxy' do
    allow(described_class::Alerta).to receive(:avisar!)
    webshare_datacenter([primeiro, segundo, terceiro, proxy_da_webshare(14, '203.0.113.14')])

    with_modified_env(WEBSHARE_LOOKUP_PROXY_ADDRESSES: '203.0.113.11,203.0.113.12,203.0.113.13,203.0.113.14') do
      described_class::Fatia.livres(described_class::ListaDaWebshare.proxies, usados: [])
    end

    expect(described_class::Alerta).to have_received(:avisar!).with('fora_da_reservada', anything, nivel: :error).once
  end

  it 'outro erro de sistema na ida a Webshare, ou o prazo curto da consulta: IP do servidor, com o motivo' do
    cliente = webshare_datacenter([])
    allow(cliente).to receive(:proxies).and_raise(Errno::EADDRNOTAVAIL)
    expect(described_class.para(account.id)).to be_nil

    webshare_datacenter([primeiro])
    expect(described_class.para(outra.id, ate: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.2)).to be_nil

    expect(queda_do_dia).to eq('webshare_sem_rede' => '1', 'webshare_sem_prazo' => '1')
  end
end

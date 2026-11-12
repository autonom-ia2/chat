require 'rails_helper'

# #2942: o proxy que caiu nas consultas grátis, com os padrões do WhatsApp Híbrido (#1516): contagem por IP, falha geral
# da Webshare, troca de no máximo uma por conta por dia com quarentena provisória de 24 h, e o Redis fora.
RSpec.describe Autonomia::FerramentasProntas::Saida::ProxyMorto do
  let(:account) { create(:account) }
  let(:registros) { Autonomia::FerramentasProntas::ProxyDaConta }
  let(:quarentenas) { Autonomia::FerramentasProntas::ProxyEmQuarentena }
  let(:fatia) { '203.0.113.11,203.0.113.12,203.0.113.13,203.0.113.14' }

  around do |example|
    with_modified_env(WEBSHARE_LOOKUP_PROXY_ADDRESSES: fatia, WEBSHARE_RESERVED_PROXY_ADDRESSES: fatia) { example.run }
  end

  before do
    zerar_saida_das_prontas
    ligar_ip_proprio(account)
    allow(Rails.logger).to receive(:warn).and_call_original
    allow(Rails.logger).to receive(:error).and_call_original
  end

  def lista(*finais)
    finais.map { |final| proxy_da_webshare(final, "203.0.113.#{final}") }
  end

  def com_ip(conta, final)
    registros.create!(account: conta, proxy_address: "203.0.113.#{final}", proxy_port: 6000, webshare_proxy_id: final.to_s,
                      assigned_at: Time.current)
  end

  def queda_do_dia
    Redis::Alfred.with { |conn| conn.hgetall("#{Autonomia::FerramentasProntas::Saida::CONTADOR}:#{Time.current.utc.to_date.iso8601}") }
  end

  it 'tres quedas seguidas trocam o IP da conta e poem o anterior de molho por 24 h' do
    webshare_datacenter(lista(11, 12, 13))
    com_ip(account, 11)

    2.times { described_class.caiu!('203.0.113.11', conta: account.id) }
    expect(quarentenas.count).to eq(0)
    described_class.caiu!('203.0.113.11', conta: account.id)

    expect(quarentenas.sole).to have_attributes(proxy_address: '203.0.113.11', reason: 'proxy_morto')
    expect(quarentenas.sole.quarantined_until).to be_within(1.minute).of(24.hours.from_now)
    expect(registros.sole.proxy_address).to eq('203.0.113.12')
    expect(Rails.logger).to have_received(:warn).with(a_string_including('anterior=203.0.113.11 novo=203.0.113.12'))
  end

  it 'sem IP livre a quarentena provisoria se desfaz: a conta segue com o IP, com alerta' do
    webshare_datacenter(lista(11))
    com_ip(account, 11)

    3.times { described_class.caiu!('203.0.113.11', conta: account.id) }

    expect(quarentenas.count).to eq(0)
    expect(registros.sole.proxy_address).to eq('203.0.113.11')
    expect(Rails.logger).to have_received(:warn).with(a_string_including('sem_ip_para_trocar'))
  end

  it 'o IP novo que tambem cai no mesmo dia deixa a conta pelo servidor, com um alerta por dia' do
    webshare_datacenter(lista(11, 12, 13))
    com_ip(account, 11)
    3.times { described_class.caiu!('203.0.113.11', conta: account.id) }

    4.times { described_class.caiu!('203.0.113.12', conta: account.id) }

    expect(quarentenas.sole.proxy_address).to eq('203.0.113.11')
    expect(registros.sole.proxy_address).to eq('203.0.113.12')
    expect(Autonomia::FerramentasProntas::Saida.para(account.id)).to be_nil
    expect(queda_do_dia).to include('ip_caiu_de_novo' => '1')
    expect(Rails.logger).to have_received(:warn).with(a_string_including('conta_no_servidor')).once
  end

  it 'falha geral (mais de 30% dos IPs com conta, ao menos 2): ninguem de molho e todos pelo servidor, com webshare_fora' do
    webshare_datacenter(lista(11, 12, 13, 14))
    outras = create_list(:account, 2)
    com_ip(account, 11)
    outras.each_with_index { |conta, vez| com_ip(conta, 12 + vez) }

    described_class.caiu!('203.0.113.11', conta: account.id)
    3.times { described_class.caiu!('203.0.113.12', conta: outras.first.id) }

    expect(quarentenas.count).to eq(0)
    expect(Rails.logger).to have_received(:error).with(a_string_including('webshare_fora'))
    ligar_ip_proprio(outras.last)
    expect(Autonomia::FerramentasProntas::Saida.para(outras.last.id)).to be_nil
    expect(queda_do_dia).to include('webshare_fora' => '1')
  end

  it 'um IP so caindo entre varios nao e falha geral' do
    webshare_datacenter(lista(11, 12, 13, 14))
    com_ip(account, 11)
    create_list(:account, 2).each_with_index { |conta, vez| com_ip(conta, 12 + vez) }

    3.times { described_class.caiu!('203.0.113.11', conta: account.id) }

    expect(quarentenas.sole.proxy_address).to eq('203.0.113.11')
    expect(Rails.logger).not_to have_received(:error).with(a_string_including('webshare_fora'))
  end

  it 'Redis fora: nao conta nem troca, avisa; e a conta sai pelo servidor' do
    webshare_datacenter(lista(11, 12))
    com_ip(account, 11)
    allow(Redis::Alfred).to receive(:with).and_raise(Redis::CannotConnectError)

    3.times { described_class.caiu!('203.0.113.11', conta: account.id) }

    expect(quarentenas.count).to eq(0)
    expect(registros.sole.proxy_address).to eq('203.0.113.11')
    expect(Rails.logger).to have_received(:warn).with(a_string_including('sem Redis (não conta nem troca)')).thrice
    expect(Autonomia::FerramentasProntas::Saida.para(account.id)).to be_nil
    expect(Rails.logger).to have_received(:warn).with(a_string_including('motivo=redis_indisponivel'))
  end
end

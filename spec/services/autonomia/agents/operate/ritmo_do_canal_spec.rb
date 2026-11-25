require 'rails_helper'

# Paridade da conversa (#3211), P5: o ritmo dos pedaços por canal, como função pura.
RSpec.describe Autonomia::Agents::Operate::RitmoDoCanal do
  let(:pedacos) { [5000, 4000, 9000, 10_000].map { |ms| { 'text' => 'x', 'type' => 'text', 'delay_ms' => ms } } }

  it 'WhatsApp oficial: cheia no 1º e ao cruzar 25 s; 1/5 nos demais; mais a pausa' do
    expect(described_class.aplicar(pedacos, whatsapp_oficial: true).pluck('delay_ms')).to eq([5000, 2800, 3800, 12_000])
  end

  it 'outros canais: espera cheia mais a pausa' do
    expect(described_class.aplicar(pedacos, whatsapp_oficial: false).pluck('delay_ms')).to eq([5000, 6000, 11_000, 12_000])
  end

  it 'pausa pós-envio' do
    expect([2500, 3000, 3001, 15_000, 15_001].map { |ms| described_class.pausa_depois_do_envio(ms) })
      .to eq([1000, 1000, 2000, 2000, 3000])
  end

  it 'não muta e mantém as outras chaves' do
    com_marca = [pedacos.first.merge('marca' => { 'k' => 1 })] + pedacos.drop(1)
    saida = described_class.aplicar(com_marca, whatsapp_oficial: false)
    expect(com_marca.pluck('delay_ms')).to eq([5000, 4000, 9000, 10_000])
    expect(saida.first['marca']).to eq('k' => 1)
  end

  it 'opção desligada, os pedaços voltam iguais' do
    agente = Autonomia::Agents::Agent.new(config: { 'conversa_ritmo_do_canal' => false })
    expect(described_class.para(pedacos, agent: agente, conversation: nil)).to equal(pedacos)
  end

  it 'sem a chave (padrão ligado), reescreve os pedaços' do
    saida = described_class.para(pedacos, agent: Autonomia::Agents::Agent.new(config: {}), conversation: nil)
    expect(saida.pluck('delay_ms')).to eq([5000, 6000, 11_000, 12_000])
  end

  it 'a Lia sem a chave: os pedaços voltam iguais, como antes' do
    lia = Autonomia::Agents::Agent.new(agent_type: 'insurance_quote', config: {})
    expect(described_class.para(pedacos, agent: lia, conversation: nil)).to equal(pedacos)
  end

  it 'com a opção, reescreve os pedaços' do
    agente = Autonomia::Agents::Agent.new(config: { 'conversa_ritmo_do_canal' => true })
    saida = described_class.para(pedacos, agent: agente, conversation: nil)
    expect(saida.pluck('delay_ms')).to eq([5000, 6000, 11_000, 12_000])
  end

  describe '.whatsapp_oficial?' do
    it 'só a caixa WhatsApp com provedor whatsapp_cloud' do
      oficial = create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
      padrao = create(:channel_whatsapp, provider: 'default', sync_templates: false, validate_provider_config: false)
      conversa = ->(canal) { create(:conversation, inbox: create(:inbox, channel: canal, account: canal.account)) }

      expect(described_class.whatsapp_oficial?(conversa.call(oficial))).to be true
      expect(described_class.whatsapp_oficial?(conversa.call(padrao))).to be false
      expect(described_class.whatsapp_oficial?(nil)).to be false
    end
  end
end

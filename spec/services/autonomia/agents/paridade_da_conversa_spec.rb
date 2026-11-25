require 'rails_helper'

# #3211: as chaves da paridade da conversa, todas desligadas por padrão.
RSpec.describe Autonomia::Agents::ParidadeDaConversa do
  def agente(config) = Autonomia::Agents::Agent.new(config: config)

  it 'sem as chaves, tudo desligado' do
    vazio = agente({})
    expect(%i[espera_a_fala? em_fila? entrega_inteira? ritmo_do_canal?].map { |p| described_class.public_send(p, vazio) })
      .to all(be(false))
  end

  it { expect(described_class.espera_a_fala?(agente('conversa_espera_a_fala' => true))).to be(true) }
  it { expect(described_class.em_fila?(agente('conversa_em_fila' => 'false'))).to be(false) }
  it { expect(described_class.ritmo_do_canal?(agente('conversa_ritmo_do_canal' => 'true'))).to be(true) }

  it 'entrega inteira só com a fila' do
    expect(described_class.entrega_inteira?(agente('conversa_entrega_inteira' => true))).to be(false)
    expect(described_class.entrega_inteira?(agente('conversa_entrega_inteira' => true, 'conversa_em_fila' => true))).to be(true)
  end

  it 'agente nil, sem config ou com config que não é Hash' do
    expect(described_class.em_fila?(nil)).to be(false)
    expect(described_class.em_fila?(Struct.new(:agent_bot).new(nil))).to be(false)
    expect(described_class.em_fila?(Struct.new(:config).new('conversa_em_fila'))).to be(false)
  end

  it 'CHAVES lista as quatro' do
    expect(described_class::CHAVES).to eq(%w[conversa_espera_a_fala conversa_em_fila conversa_entrega_inteira conversa_ritmo_do_canal])
  end
end

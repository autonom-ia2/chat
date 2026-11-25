require 'rails_helper'

# #3211 (decisão do Rodrigo, 25/11): as chaves da paridade da conversa nascem ligadas em todo agente, menos na Lia
# (`insurance_quote`). Valor gravado manda; só a chave ausente ou nula segue o padrão do tipo.
RSpec.describe Autonomia::Agents::ParidadeDaConversa do
  let(:opcoes) { %i[espera_a_fala? em_fila? entrega_inteira? ritmo_do_canal?] }

  def agente(config, agent_type: 'custom') = Autonomia::Agents::Agent.new(config: config, agent_type: agent_type)

  def lia(config = {}) = agente(config, agent_type: 'insurance_quote')

  def todas(agent) = opcoes.map { |opcao| described_class.public_send(opcao, agent) }

  it 'sem as chaves, tudo ligado' do
    expect(todas(agente({}))).to all(be(true))
  end

  it 'chave nula segue o padrão: ligada' do
    expect(described_class.em_fila?(agente('conversa_em_fila' => nil))).to be(true)
  end

  it 'valor gravado desliga: false, "false" e "0"', :aggregate_failures do
    expect(described_class.espera_a_fala?(agente('conversa_espera_a_fala' => false))).to be(false)
    expect(described_class.em_fila?(agente('conversa_em_fila' => 'false'))).to be(false)
    expect(described_class.ritmo_do_canal?(agente('conversa_ritmo_do_canal' => '0'))).to be(false)
  end

  it 'valor gravado liga: true e "true"', :aggregate_failures do
    expect(described_class.espera_a_fala?(agente('conversa_espera_a_fala' => true))).to be(true)
    expect(described_class.ritmo_do_canal?(agente('conversa_ritmo_do_canal' => 'true'))).to be(true)
  end

  it 'a Lia sem as chaves: tudo desligado, como antes' do
    expect(todas(lia)).to all(be(false))
  end

  it 'a Lia com true gravado: ligada', :aggregate_failures do
    expect(described_class.em_fila?(lia('conversa_em_fila' => true))).to be(true)
    expect(described_class.espera_a_fala?(lia('conversa_em_fila' => true))).to be(false)
  end

  describe 'entrega inteira só com a fila efetiva' do
    it 'as duas ausentes: ligada' do
      expect(described_class.entrega_inteira?(agente({}))).to be(true)
    end

    it 'com a fila desligada: desligada, mesmo com a entrega gravada true' do
      expect(described_class.entrega_inteira?(agente('conversa_entrega_inteira' => true, 'conversa_em_fila' => false))).to be(false)
    end

    it 'com a entrega desligada: desligada' do
      expect(described_class.entrega_inteira?(agente('conversa_entrega_inteira' => false))).to be(false)
    end

    it 'na Lia, só a entrega gravada não basta: a fila dela segue desligada', :aggregate_failures do
      expect(described_class.entrega_inteira?(lia('conversa_entrega_inteira' => true))).to be(false)
      expect(described_class.entrega_inteira?(lia('conversa_entrega_inteira' => true, 'conversa_em_fila' => true))).to be(true)
    end
  end

  it 'agente de verdade com config nil ou que não é Hash: o padrão do tipo', :aggregate_failures do
    sem_config = agente({}).tap { |agent| agent.config = nil }
    texto = agente({}).tap { |agent| agent.config = 'conversa_em_fila' }

    expect(todas(sem_config)).to all(be(true))
    expect(described_class.em_fila?(texto)).to be(true)
    expect(described_class.em_fila?(lia.tap { |agent| agent.config = nil })).to be(false)
  end

  it 'o que não é agente fica desligado: nil, vínculo sem agente, Struct com config', :aggregate_failures do
    expect(described_class.em_fila?(nil)).to be(false)
    expect(described_class.em_fila?(Struct.new(:agent_bot).new(nil))).to be(false)
    expect(described_class.em_fila?(Struct.new(:config).new({}))).to be(false)
    expect(described_class.em_fila?(Struct.new(:config, :agent_type).new({}, 'custom'))).to be(false)
  end

  # Revisão do #3218 (item 3). Pega: a chave da instalação não desligar o padrão, ou passar por cima do valor gravado.
  describe 'chave da instalação AI_AGENT_CONVERSA_PADRAO_LIGADO' do
    it 'false: a chave ausente vale desligada (como no #3213); valor gravado continua mandando', :aggregate_failures do
      with_modified_env AI_AGENT_CONVERSA_PADRAO_LIGADO: 'false' do
        expect(todas(agente({}))).to all(be(false))
        expect(described_class.em_fila?(agente('conversa_em_fila' => true))).to be(true)
        expect(described_class.espera_a_fala?(agente('conversa_espera_a_fala' => false))).to be(false)
        expect(todas(lia)).to all(be(false))
      end
    end

    it 'true (ou ausente): a chave ausente vale ligada; a Lia segue desligada', :aggregate_failures do
      with_modified_env AI_AGENT_CONVERSA_PADRAO_LIGADO: 'true' do
        expect(todas(agente({}))).to all(be(true))
        expect(todas(lia)).to all(be(false))
      end
    end
  end

  it 'CHAVES lista as quatro' do
    expect(described_class::CHAVES).to eq(%w[conversa_espera_a_fala conversa_em_fila conversa_entrega_inteira conversa_ritmo_do_canal])
  end
end

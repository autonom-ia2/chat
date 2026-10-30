require 'rails_helper'

# F3 do tema 8 (#1429): a linha "Base de seguros" da página do agente. Com que base o agente trabalha, se há uma nova,
# e a situação: em_dia | sem_base | antiga | conta_mudou. nil = a linha não aparece.
RSpec.describe Autonomia::Agents::BaseDeSeguros do
  let(:conta) { conta_da_fase2 }
  let(:bloco) { Autonomia::Segmentos::Bloco }
  let(:corretora) { 'seguros/corretora' }
  let(:seguradora) { 'seguros/seguradora' }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', AUTONOMIA_PACOTES_ENABLED: 'true') { example.run } }

  def tipo_da_conta(perfil)
    nicho = Autonomia::Agents::Nicho
    conta.update!(internal_attributes: conta.internal_attributes.to_h.merge(nicho::NICHO_KEY => 'seguros', nicho::PERFIL_KEY => perfil))
  end

  def conta_geral
    nicho = Autonomia::Agents::Nicho
    conta.update!(internal_attributes: conta.internal_attributes.to_h.except(nicho::NICHO_KEY, nicho::PERFIL_KEY))
  end

  def marca(segmento, versao: bloco.versao(segmento), texto: bloco.for_segmento(segmento))
    { 'segmento' => segmento, 'versao' => versao, 'texto' => texto }
  end

  def agente(config = {}, **extras)
    criar_principal(conta, config: { 'with_knowledge' => false }.merge(config), **extras)
  end

  def agente_com_base(base)
    agente({ 'base' => base })
  end

  def situacao_de(agent)
    described_class.new(agent).to_h
  end

  before { tipo_da_conta('corretora') }

  it 'sem marca numa conta de seguros: sem_base, com a base nova e a data dela' do
    resultado = situacao_de(agente)

    expect(resultado).to include(situacao: 'sem_base', atual: nil, pode_atualizar: true, desfazer: nil)
    expect(resultado[:nova]).to eq(segmento: corretora, versao: bloco.versao(corretora),
                                   data: bloco.data_da_versao(corretora, bloco.versao(corretora)))
  end

  it 'marca com texto nil: sem_base' do
    resultado = situacao_de(agente_com_base(marca(nil, versao: nil, texto: nil)))

    expect(resultado[:situacao]).to eq('sem_base')
  end

  it 'a base atual do segmento: em_dia, sem base nova' do
    resultado = situacao_de(agente_com_base(marca(corretora)))

    expect(resultado).to include(situacao: 'em_dia', nova: nil, pode_atualizar: false)
    expect(resultado[:atual]).to eq(segmento: corretora, data: bloco.data_da_versao(corretora, bloco.versao(corretora)))
  end

  it 'outra versão do mesmo segmento: antiga; versão sem data registrada mostra a data nil' do
    resultado = situacao_de(agente_com_base(marca(corretora, versao: 'antiga000000', texto: 'Texto antigo do ramo.')))

    expect(resultado).to include(situacao: 'antiga', pode_atualizar: true)
    expect(resultado[:atual]).to eq(segmento: corretora, data: nil)
    expect(resultado[:nova][:segmento]).to eq(corretora)
  end

  it 'segmento gravado diferente do da conta: conta_mudou, com a base do tipo novo' do
    resultado = situacao_de(agente_com_base(marca(seguradora)))

    expect(resultado).to include(situacao: 'conta_mudou', pode_atualizar: true)
    expect(resultado[:atual][:segmento]).to eq(seguradora)
    expect(resultado[:nova][:segmento]).to eq(corretora)
  end

  it 'conta geral e agente sem base: a linha não aparece' do
    conta_geral

    expect(situacao_de(agente)).to be_nil
  end

  it 'conta geral e agente com base: conta_mudou, sem base nova para trocar' do
    conta_geral

    resultado = situacao_de(agente_com_base(marca(corretora)))

    expect(resultado).to include(situacao: 'conta_mudou', nova: nil, pode_atualizar: false)
  end

  it 'sem a Fase 2: nada' do
    Autonomia::Agents::Fase2.desligar!(conta)

    expect(situacao_de(agente)).to be_nil
  end

  it 'a Lia (instrução mantida) não tem linha' do
    lia = Autonomia::Agents::Agent.new(account: conta, agent_type: 'insurance_quote')

    expect(described_class.elegivel?(lia)).to be(false)
    expect(situacao_de(lia)).to be_nil
  end

  it 'o Guia (system_key) não tem linha' do
    guia = agente({ 'system_key' => 'guia' })

    expect(described_class.elegivel?(guia)).to be(false)
  end

  it 'falha ao ler o tipo da conta: a linha some, sem erro' do
    allow(Autonomia::Agents::Nicho).to receive(:for).and_raise(StandardError, 'quebrou')

    expect(situacao_de(agente_com_base(marca(corretora)))).to be_nil
  end

  it 'agente sem instrução não pode atualizar (a troca precisa gravar versão)' do
    resultado = situacao_de(agente(instruction: nil))

    expect(resultado).to include(situacao: 'sem_base', pode_atualizar: false)
  end

  it 'nunca devolve o texto da base' do
    resultado = situacao_de(agente_com_base(marca(seguradora)))

    expect(resultado.to_json).not_to include(bloco.for_segmento(seguradora))
    expect(resultado.to_json).not_to include(bloco.for_segmento(corretora))
  end

  it 'logo depois de atualizar, oferece o Desfazer com a base de antes' do
    agent = agente_com_base(marca(seguradora))
    agent.trocar_base!(described_class.new(agent).marca_nova)

    resultado = situacao_de(agent.reload)

    expect(resultado).to include(situacao: 'em_dia')
    expect(resultado[:desfazer]).to eq(anterior: { segmento: seguradora, data: bloco.data_da_versao(seguradora, bloco.versao(seguradora)) })
  end
end

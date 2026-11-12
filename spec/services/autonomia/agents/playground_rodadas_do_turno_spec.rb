require 'rails_helper'

# #2918, régua do Rodrigo: o que o dono testa é o que o cliente recebe. O Testar (`Playground`) e o Copiloto (`Copilot`)
# pedem as rodadas pela MESMA função do atendimento (`RodadasDoTurno.para`): o agente com pronta testa e sugere com as
# 3 rodadas do Experimente, e o com ajudante, com as 6 dele. A Lia segue fora, no desvio do Testar dela (#2382): no
# Testar e no Copiloto ela fica com uma rodada, como antes.
RSpec.describe Autonomia::Agents::Playground do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true, 'autonomia_insurance_enabled' => true }) }
  let(:answerer) { instance_double(Autonomia::Agents::Answerer, answer: :resultado) }
  let(:pedidos) { [] }
  let(:rodadas_do_turno) { Autonomia::Agents::RodadasDoTurno }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', INSURANCE_QUOTING_ENABLED: 'true') { example.run } }

  before do
    resolver_hosts_das_prontas
    ligar_consultas(account)
    account.enable_features!(Autonomia::FerramentasProntas::Fontes::Ncm::FLAG)
    allow(Autonomia::Agents::Answerer).to receive(:new) do |**kwargs|
      pedidos << kwargs.slice(:max_rodadas, :max_segundos, :uma_escrita_por_turno)
      answerer
    end
  end

  def criar_agente
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.', config: { 'with_knowledge' => false })
  end

  # As rodadas que o `Answerer` usa: as pedidas sobre o padrão dele (uma rodada, sem relógio próprio).
  def efetivas(pedido)
    { max_rodadas: 1, max_segundos: nil }.merge(pedido)
  end

  def no_testar(agente)
    Autonomia::Agents::Playground.new(agent: agente, message: 'qual o NCM do café torrado?').run
    efetivas(pedidos.last)
  end

  def no_copiloto(agente)
    Autonomia::Agents::Copilot.new(agent: agente, message: 'qual o NCM do café torrado?').suggest
    efetivas(pedidos.last)
  end

  # As rodadas das prontas, com a escrita uma vez por turno (a revisão de segurança do #2918).
  def tres_rodadas
    { max_rodadas: Autonomia::FerramentasProntas::RODADAS_POR_RESPOSTA,
      max_segundos: Autonomia::FerramentasProntas::PRAZO_DAS_RODADAS, uma_escrita_por_turno: true }
  end

  it 'o agente com pronta tem no atendimento as rodadas do Experimente' do
    agente = criar_agente
    incluir_pronta('ncm', conta: account, agente: agente)

    expect(rodadas_do_turno.para(agente)).to eq(tres_rodadas)
  end

  it 'o Testar do agente com pronta pede as mesmas rodadas do atendimento' do
    agente = criar_agente
    incluir_pronta('ncm', conta: account, agente: agente)

    expect(no_testar(agente)).to eq(tres_rodadas)
  end

  it 'o Copiloto do agente com pronta pede as mesmas rodadas do atendimento' do
    agente = criar_agente
    incluir_pronta('ncm', conta: account, agente: agente)

    expect(no_copiloto(agente)).to eq(tres_rodadas)
  end

  it 'o Testar e o Copiloto pedem pela mesma função do atendimento', :aggregate_failures do
    agente = criar_agente
    allow(rodadas_do_turno).to receive(:para).and_call_original

    no_testar(agente)
    no_copiloto(agente)

    expect(rodadas_do_turno).to have_received(:para).with(agente).twice
  end

  it 'com a flag da fonte desligada, o Testar e o Copiloto ficam com uma rodada, como o atendimento', :aggregate_failures do
    agente = criar_agente
    incluir_pronta('ncm', conta: account, agente: agente)
    account.disable_features!(Autonomia::FerramentasProntas::Fontes::Ncm::FLAG)

    expect(no_testar(agente)).to eq(max_rodadas: 1, max_segundos: nil)
    expect(no_copiloto(agente)).to eq(max_rodadas: 1, max_segundos: nil)
  end

  it 'o agente sem pronta testa e sugere com uma rodada, como antes', :aggregate_failures do
    agente = criar_agente

    expect(no_testar(agente)).to eq(max_rodadas: 1, max_segundos: nil)
    expect(no_copiloto(agente)).to eq(max_rodadas: 1, max_segundos: nil)
  end

  it 'o agente com ajudante (e pronta) testa e sugere com as 6 rodadas do ajudante', :aggregate_failures do
    account.update!(internal_attributes: account.internal_attributes.merge('autonomia_agents_fase2' => true))
    agente = criar_agente
    incluir_pronta('ncm', conta: account, agente: agente)
    vincular(agente, criar_ajudante(account))

    expect(no_testar(agente)).to eq(Autonomia::Agents::Ajudantes.rodadas(agente))
    expect(no_copiloto(agente)).to eq(Autonomia::Agents::Ajudantes.rodadas(agente))
    expect(no_testar(agente)[:max_rodadas]).to eq(6)
  end

  # O Testar da Lia fica no desvio dela (`Playground.como_no_atendimento?`, TODO #2382): uma rodada, como antes.
  it 'a Lia segue com o Testar e o Copiloto de antes, mesmo com uma linha de pronta', :aggregate_failures do
    lia = Autonomia::Insurance::QuoteAgent::Builder.new(account: account, nome_agente: 'Lia', nome_corretora: 'X').call
    pronta_ja_incluida('ncm', conta: account, agente: lia)

    expect(no_testar(lia)).to eq(max_rodadas: 1, max_segundos: nil)
    expect(no_copiloto(lia)).to eq(max_rodadas: 1, max_segundos: nil)
  end

  it 'no atendimento, a Lia segue com a regra dela' do
    lia = Autonomia::Insurance::QuoteAgent::Builder.new(account: account, nome_agente: 'Lia', nome_corretora: 'X').call
    pronta_ja_incluida('ncm', conta: account, agente: lia)

    expect(rodadas_do_turno.para(lia)).to eq(Autonomia::Insurance::QuoteAgent::Builder.rodadas_do_turno(lia))
  end
end

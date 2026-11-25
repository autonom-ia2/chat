require 'rails_helper'

# #2154: a marca do turno do agente em curso, para a IA de Atribuição não entregar a conversa no meio dele.
RSpec.describe Autonomia::Agents::Operate::TurnoEmCurso do
  let(:conversa) { 987_654 }
  let(:chave) { described_class.chave(conversa) }

  before { Redis::Alfred.delete(chave) }

  it 'o teto do turno sai das configurações e cobre as rodadas da Lia, o debounce e a cadeia', :aggregate_failures do
    runner = Autonomia::Agents::Specialists::Runner
    lia = Autonomia::Insurance::QuoteAgent::Builder::RODADAS_DA_LIA * (runner::SEGUNDOS_DE_FERRAMENTA + runner::SEGUNDOS_POR_CHAMADA)

    expect(described_class.teto_do_turno).to be > lia.seconds
    expect(described_class.teto_do_turno).to be > Autonomia::Agents::Config::OPERATE_DEBOUNCE_MAX_SECONDS
  end

  # #3211: com as opções da paridade desligadas (sem agente, na Lia ou gravadas `false`), o teto é exatamente o de antes;
  # o agente com elas ligadas (o padrão) ganha a janela da espera pela fala e da fila.
  it 'sem as opções da paridade, o teto do turno é o de sempre', :aggregate_failures do
    runner = Autonomia::Agents::Specialists::Runner
    lia = Autonomia::Insurance::QuoteAgent::Builder::RODADAS_DA_LIA * (runner::SEGUNDOS_DE_FERRAMENTA + runner::SEGUNDOS_POR_CHAMADA)
    ia = [lia, Autonomia::Agents::Ajudantes::PRAZO_DA_RESPOSTA, Autonomia::FerramentasProntas::PRAZO_DAS_RODADAS,
          Crm::Ai::ResponsesClient::REQUEST_TIMEOUT].max
    cadeia = Autonomia::Agents::Config::HUMANIZE[:max_total_delay_ms] / 1000
    de_sempre = Autonomia::Agents::Config::OPERATE_DEBOUNCE_MAX_SECONDS + Autonomia::Agents::Operate::EsperaDoAssunto::TETO +
                (ia + cadeia).seconds

    expect(described_class.teto_do_turno).to eq(de_sempre)
    expect(described_class.teto_do_turno(Autonomia::Agents::Agent.new(config: paridade_desligada))).to eq(de_sempre)
    expect(described_class.teto_do_turno(Autonomia::Agents::Agent.new(agent_type: 'insurance_quote', config: {}))).to eq(de_sempre)
  end

  it 'agente sem as chaves (padrão ligado): o teto cobre a espera pela fala e a fila' do
    espera = Autonomia::Agents::Operate::EsperaDaFala

    expect(described_class.teto_do_turno(Autonomia::Agents::Agent.new(config: {})))
      .to eq(described_class.teto_do_turno + (espera::ESPERA_MAXIMA - Autonomia::Agents::Config::OPERATE_DEBOUNCE_MAX_SECONDS) +
             espera::TETO_DA_FILA)
  end

  it 'com a espera pela fala e a fila, o teto do turno cobre as duas' do
    espera = Autonomia::Agents::Operate::EsperaDaFala
    agente = Autonomia::Agents::Agent.new(config: { 'conversa_espera_a_fala' => true, 'conversa_em_fila' => true })

    minimo = espera::ESPERA_MAXIMA + espera::TETO_DA_FILA + Autonomia::Agents::Operate::EsperaDoAssunto::TETO

    expect(described_class.teto_do_turno(agente)).to be >= minimo
  end

  # #2918: a composição, não só o valor de hoje (o termo da Lia é maior e esconderia a falta do termo das prontas).
  it 'o teto do turno cobre o prazo das rodadas do agente com pronta, sem depender da Lia nem do ajudante' do
    stub_const('Autonomia::Insurance::QuoteAgent::Builder::RODADAS_DA_LIA', 0)
    stub_const('Autonomia::Agents::Ajudantes::PRAZO_DA_RESPOSTA', 0)

    expect(described_class.teto_do_turno).to be > Autonomia::FerramentasProntas::PRAZO_DAS_RODADAS.seconds
  end

  it 'abre com o teto do turno; a mensagem mais nova toma a marca', :aggregate_failures do
    described_class.abrir(conversa, 1)
    expect(Redis::Alfred.ttl(chave)).to be_within(5).of(described_class.teto_do_turno.to_i)

    described_class.abrir(conversa, 2)
    expect(Redis::Alfred.get(chave)).to eq('2')
    expect(described_class.em_curso?(conversa)).to be(true)
  end

  it 'abre com o teto do agente: com a fila ligada, maior que o de sempre', :aggregate_failures do
    agente = Autonomia::Agents::Agent.new(config: { 'conversa_em_fila' => true })
    described_class.abrir(conversa, 1, agente)

    expect(Redis::Alfred.ttl(chave)).to be_within(5).of(described_class.teto_do_turno(agente).to_i)
    expect(described_class.teto_do_turno(agente)).to be > described_class.teto_do_turno
  end

  it 'renova só a marca do próprio turno (uma cadeia velha não prolonga nem sobrescreve a nova)', :aggregate_failures do
    described_class.abrir(conversa, 2)

    expect(described_class.renovar(conversa, 1)).to be(false)
    expect(Redis::Alfred.get(chave)).to eq('2')
    expect(Redis::Alfred.ttl(chave)).to be > described_class::TTL_DA_CADEIA.to_i

    expect(described_class.renovar(conversa, 2)).to be(true)
    expect(Redis::Alfred.ttl(chave)).to be_between(1, described_class::TTL_DA_CADEIA.to_i)
  end

  it 'renovar não cria marca que não existe' do
    described_class.renovar(conversa, 1)

    expect(described_class.em_curso?(conversa)).to be(false)
  end

  it 'solta só a marca do próprio turno', :aggregate_failures do
    described_class.abrir(conversa, 2)

    described_class.soltar(conversa, 1)
    expect(described_class.em_curso?(conversa)).to be(true)

    described_class.soltar(conversa, 2)
    expect(described_class.em_curso?(conversa)).to be(false)
  end

  it 'nunca levanta: sem Redis, a entrega segue', :aggregate_failures do
    allow(Redis::Alfred).to receive(:set).and_raise(Redis::CannotConnectError)
    allow(Redis::Alfred).to receive(:exists?).and_raise(Redis::CannotConnectError)

    expect(described_class.abrir(conversa, 1)).to be_nil
    expect(described_class.em_curso?(conversa)).to be(false)
  end
end

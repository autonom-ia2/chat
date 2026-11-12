require 'rails_helper'

# AS RODADAS DO AGENTE COM FERRAMENTA PRONTA (#2918, decisão do Rodrigo em 11/11/2026: "Sim... pode sim!"). Com uma rodada,
# o atendimento ficava atrás do Experimente da vitrine, que faz três: a NCM "café torrado" volta o grupo 0901.2, e o código
# da nota (0901.21.00) só vem na segunda consulta, pelo grupo. O agente com ao menos uma pronta que ele RECEBE no turno
# (a flag dela ligada na conta) ganha as rodadas do Experimente; a ordem é ajudante, Lia, pronta e o padrão.
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true, 'autonomia_insurance_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:prontas) { Autonomia::FerramentasProntas }

  def criar_agente
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.', config: { 'with_knowledge' => false })
  end

  def caixa_com_mensagem(agente)
    create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :incoming, content: 'oi')
    lia_na_caixa(agente, inbox: inbox, agent_bot: agent_bot)
  end

  def rodadas_pedidas(agente)
    agent_inbox = caixa_com_mensagem(agente)
    recebido = nil
    allow(Autonomia::Agents::Answerer).to receive(:new).and_wrap_original do |original, **kwargs|
      recebido = kwargs.slice(:max_rodadas, :max_segundos)
      original.call(**kwargs)
    end
    allow_any_instance_of(Autonomia::Agents::Answerer).to receive(:answer).and_return(nil) # rubocop:disable RSpec/AnyInstance
    described_class.new(conversation: conversation, agent_inbox: agent_inbox,
                        reply_to_message_id: conversation.messages.incoming.last.id).perform
    recebido
  end

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', INSURANCE_QUOTING_ENABLED: 'true') { example.run } }

  before do
    resolver_hosts_das_prontas
    ligar_consultas(account)
    account.enable_features!(Autonomia::FerramentasProntas::Fontes::Ncm::FLAG)
  end

  it 'o agente sem pronta continua com uma rodada e o orçamento padrão' do
    expect(rodadas_pedidas(criar_agente)).to eq(max_rodadas: 1, max_segundos: nil)
  end

  it 'o agente sem pronta, mas com uma ferramenta cadastrada, continua com uma rodada' do
    agente = criar_agente
    Autonomia::Agents::Tool.create!(account: account, agent: agente, name: 'Pedido', slug: 'consultar_pedido', http_method: 'GET',
                                    endpoint_url: 'https://api.example.com/pedidos', param_schema: [])

    expect(rodadas_pedidas(agente)).to eq(max_rodadas: 1, max_segundos: nil)
  end

  it 'o agente com pronta tem as rodadas do Experimente, e o relógio não corta nenhuma', :aggregate_failures do
    agente = criar_agente
    incluir_pronta('ncm', conta: account, agente: agente)

    pedido = rodadas_pedidas(agente)

    expect(pedido[:max_rodadas]).to eq(3)
    expect(pedido[:max_rodadas]).to eq(Autonomia::FerramentasProntas::Experimente::ComModelo::MAX_RODADAS)
    # Cada rodada cabe inteira: a ida ao modelo no teto dela e a janela de 8 s da consulta.
    rodada_inteira = Crm::Ai::ResponsesClient::REQUEST_TIMEOUT + Autonomia::Agents::Tools::ConsultaNoTurno::ESPERA_DO_TURNO
    expect(pedido[:max_segundos]).to eq(3 * rodada_inteira)
  end

  it 'a pronta desligada no agente não conta' do
    agente = criar_agente
    incluir_pronta('ncm', conta: account, agente: agente).update!(enabled: false)

    expect(rodadas_pedidas(agente)).to eq(max_rodadas: 1, max_segundos: nil)
  end

  it 'com a flag da fonte desligada na conta, a pronta não entra no turno e o agente fica com uma rodada' do
    agente = criar_agente
    incluir_pronta('ncm', conta: account, agente: agente)
    account.disable_features!(Autonomia::FerramentasProntas::Fontes::Ncm::FLAG)

    expect(rodadas_pedidas(agente)).to eq(max_rodadas: 1, max_segundos: nil)
  end

  it 'com a flag das prontas desligada na conta, o agente fica com uma rodada' do
    agente = criar_agente
    incluir_pronta('ncm', conta: account, agente: agente)
    account.disable_features!(Autonomia::FerramentasProntas::FLAG)

    expect(rodadas_pedidas(agente)).to eq(max_rodadas: 1, max_segundos: nil)
  end

  it 'vale a flag da conta do agente: ligada só em outra conta, a pronta dele não dá rodadas' do
    agente = criar_agente
    incluir_pronta('ncm', conta: account, agente: agente)
    account.disable_features!(Autonomia::FerramentasProntas::Fontes::Ncm::FLAG)
    outra = create(:account)
    ligar_consultas(outra)
    outra.enable_features!(Autonomia::FerramentasProntas::Fontes::Ncm::FLAG)

    expect(rodadas_pedidas(agente)).to eq(max_rodadas: 1, max_segundos: nil)
  end

  it 'o agente com ajudante e pronta fica com as rodadas do ajudante (vem antes)', :aggregate_failures do
    account.update!(internal_attributes: account.internal_attributes.merge('autonomia_agents_fase2' => true))
    agente = criar_agente
    incluir_pronta('ncm', conta: account, agente: agente)
    vincular(agente, criar_ajudante(account))

    pedido = rodadas_pedidas(agente)

    expect(pedido).to eq(Autonomia::Agents::Ajudantes.rodadas(agente))
    expect(pedido[:max_rodadas]).to eq(6)
  end

  it 'a Lia, mesmo com uma linha de pronta gravada, segue com a regra dela', :aggregate_failures do
    lia = Autonomia::Insurance::QuoteAgent::Builder.new(account: account, nome_agente: 'Lia', nome_corretora: 'X').call
    pronta_ja_incluida('ncm', conta: account, agente: lia)

    pedido = rodadas_pedidas(lia)

    expect(pedido).to eq(Autonomia::Insurance::QuoteAgent::Builder.rodadas_do_turno(lia))
    expect(pedido[:max_rodadas]).to eq(6)
  end

  # Hoje o termo da Lia domina o teto; o spec guarda o caso de as contas mudarem.
  it 'o teto do turno em curso cobre o prazo das rodadas das prontas' do
    expect(Autonomia::Agents::Operate::TurnoEmCurso.teto_do_turno).to be > prontas::PRAZO_DAS_RODADAS.seconds
  end
end

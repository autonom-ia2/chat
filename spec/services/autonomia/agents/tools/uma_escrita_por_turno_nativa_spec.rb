require 'rails_helper'

# #2918, revisão de segurança: a trava da escrita vale também para a nativa que ESCREVE. A injeção que repete o POST
# repete "marcar horário", e isso criava duas reuniões. Nas rodadas das prontas, `agendar_reuniao` (escreve) roda uma vez
# por turno; `horarios_disponiveis` (lê) roda quantas vezes o modelo pedir. A classificação é a declaração da própria
# ferramenta (`escreve?`), nunca o nome. As nativas são as de verdade; só a execução delas é dublada (sem página de
# agendamento), e o modelo chama uma vez por rodada, em duas rodadas.
RSpec.describe Autonomia::Agents::Tools::UmaEscritaPorTurno do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.', config: { 'with_knowledge' => false })
  end
  let(:agent_inbox) { Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot) }
  let(:delivery) { Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, origin_message_id: 77) }
  let(:nativas) { Autonomia::Agents::Tools::Native }
  let(:execucoes) { Hash.new(0) }
  let(:saidas) { [] }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  before do
    resolver_hosts_das_prontas
    ligar_consultas(account)
    account.enable_features!(Autonomia::FerramentasProntas::Fontes::Ncm::FLAG)
    incluir_pronta('ncm', conta: account, agente: agent)
    na_agenda(nativas::AgendarReuniao, '{"ok":true,"reuniao":"marcada"}')
    na_agenda(nativas::HorariosDisponiveis, '{"horarios":["terça 11:00"]}')
    allow(Autonomia::Agents::Tools::Registry).to receive(:for_agent)
      .and_return([nativas::AgendarReuniao, nativas::HorariosDisponiveis])
  end

  # A nativa de verdade no catálogo, com a execução contada no lugar da agenda.
  def na_agenda(nativa, saida)
    allow(nativa).to receive(:openai_schema).and_return({ type: 'function', name: nativa.slug, parameters: {} })
    allow(nativa).to receive(:new) do |**_kwargs|
      instance_double(nativa).tap do |ferramenta|
        allow(ferramenta).to receive(:call) { (execucoes[nativa.slug] += 1) && saida }
      end
    end
  end

  # O modelo chama `slug` uma vez em cada uma de duas rodadas, e responde.
  def o_modelo_chama_duas_vezes(slug)
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: 'ai-credential'))
    client = instance_double(Crm::Ai::ResponsesClient)
    allow(client).to receive(:create_with_tool_executor) do |**_kwargs, &executor|
      %w[c1 c2].each { |id| saidas.concat(executor.call([{ 'name' => slug, 'call_id' => id, 'arguments' => '{}' }])) }
      { text: { reply: 'ok', confidence: 0.9, should_handoff: false, handoff_reason: nil, used_snippet_ids: [],
                answered_from_knowledge: false }.to_json }
    end
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
  end

  def responder
    Autonomia::Agents::Answerer.new(agent: agent, query: 'marca terça 11h', trust_instruction: true, delivery: delivery,
                                    **Autonomia::Agents::RodadasDoTurno.para(agent)).answer
  end

  it 'marcar horário duas vezes no turno: a segunda não roda e o modelo lê que já foi feita', :aggregate_failures do
    o_modelo_chama_duas_vezes('agendar_reuniao')

    responder

    expect(execucoes['agendar_reuniao']).to eq(1)
    expect(saidas.pluck(:output)).to eq(['{"ok":true,"reuniao":"marcada"}', described_class::JA_FEITA])
  end

  it 'consultar horários duas vezes no turno: as duas rodam', :aggregate_failures do
    o_modelo_chama_duas_vezes('horarios_disponiveis')

    responder

    expect(execucoes['horarios_disponiveis']).to eq(2)
    expect(saidas.pluck(:output)).to all(eq('{"horarios":["terça 11:00"]}'))
  end
end

require 'rails_helper'

RSpec.describe 'Autonomia BE-05 builder resume writer', type: :model do
  let(:account) { create(:account) }
  let(:builder_payload) do
    {
      'name' => 'Nome gerado', 'agent_type' => 'sdr', 'instruction' => 'Instrução gerada',
      'scaffold' => 'Andaime gerado', 'human_card' => 'Resumo gerado', 'greeting' => 'Saudação gerada',
      'fallback_message' => 'Fallback gerado', 'handoff_rule' => 'Regra gerada',
      'starter_questions' => ['Pergunta gerada'], 'tone' => 'Tom gerado',
      'guardrails' => ['Limite novo'], 'voice' => 'masculina', 'needs_more_info' => false,
      'next_question' => '', 'user_asked_to_close' => false
    }
  end

  it 'accepts the complete creation schema when the first generation has no linked agent' do
    thread = Autonomia::Agents::BuildThread.create!(
      account: account, state: { 'no_materials_declared' => true }
    )
    builder = Autonomia::Agents::Builder.new(account: account, build_thread: thread)
    client = instance_double(Crm::Ai::ResponsesClient, create: { text: builder_payload.to_json })
    allow(builder).to receive(:client).and_return(client)

    builder.run!(thread.begin_build!)

    agent = thread.reload.agent
    expect(agent).to have_attributes(
      name: 'Nome gerado', agent_type: 'sdr', instruction: 'Instrução gerada',
      greeting: 'Saudação gerada', fallback_message: 'Fallback gerado', tone: 'Tom gerado',
      actuation: 'external'
    )
    expect(agent.config).to include('voice' => 'masculina', 'guardrails' => ['Limite novo'])
    expect(agent.starter_questions).to eq(['Pergunta gerada'])
  end

  it 'accepts the complete schema for an E1/E2 draft that was linked before closing' do
    draft = Autonomia::Agents::Agent.create!(
      account: account, name: 'Novo agente', agent_type: 'custom', mode: :guided, status: :draft,
      enabled: false
    )
    thread = Autonomia::Agents::BuildThread.create!(
      account: account, agent: draft, state: { 'no_materials_declared' => true }
    )
    builder = Autonomia::Agents::Builder.new(account: account, build_thread: thread)
    client = instance_double(Crm::Ai::ResponsesClient, create: { text: builder_payload.to_json })
    allow(builder).to receive(:client).and_return(client)

    builder.run!(thread.begin_build!)

    expect(draft.reload).to have_attributes(
      name: 'Nome gerado', agent_type: 'sdr', instruction: 'Instrução gerada',
      greeting: 'Saudação gerada', fallback_message: 'Fallback gerado', tone: 'Tom gerado'
    )
    expect(draft.config).to include('voice' => 'masculina', 'guardrails' => ['Limite novo'])
    expect(draft.starter_questions).to eq(['Pergunta gerada'])
  end

  it 'applies only the D22 fields when a guided agent already has instruction' do
    agent = Autonomia::Agents::Agent.create!(
      account: account, name: 'Clara antiga', agent_type: 'custom', mode: :guided, status: :draft,
      enabled: false, instruction: 'Instrução atual', greeting: 'Oi atual', fallback_message: 'Fallback atual',
      handoff_rule: 'Regra atual', starter_questions: ['Pergunta atual'], tone: 'Tom atual',
      actuation: :external,
      config: {
        'voice' => 'feminina', 'guardrails' => ['Limite atual'], 'with_knowledge' => false,
        'handoff_target_type' => 'member', 'response_window' => 'outside_business_hours'
      }
    )
    inbox = create(:inbox, account: account)
    bot = AgentBot.create!(account: account, name: agent.name, bot_type: :webhook, outgoing_url: nil)
    link = Autonomia::Agents::AgentInbox.create!(account: account, agent: agent, inbox: inbox, agent_bot: bot)
    thread = Autonomia::Agents::BuildThread.create!(account: account, agent: agent)
    builder = Autonomia::Agents::Builder.new(account: account, build_thread: thread)
    client = instance_double(Crm::Ai::ResponsesClient, create: { text: builder_payload.to_json })
    allow(builder).to receive(:client).and_return(client)
    allow(builder).to receive(:builder_actuation).and_return('internal')

    builder.run!(thread.begin_build!)

    agent.reload
    expect(agent).to have_attributes(
      name: 'Clara antiga', agent_type: 'custom', greeting: 'Oi atual', fallback_message: 'Fallback atual',
      tone: 'Tom atual', actuation: 'external', instruction: 'Instrução gerada',
      human_card: 'Resumo gerado', scaffold: 'Andaime gerado', handoff_rule: 'Regra gerada'
    )
    expect(agent.starter_questions).to eq(['Pergunta atual'])
    expect(agent.config).to include(
      'voice' => 'feminina', 'guardrails' => ['Limite novo'], 'with_knowledge' => false,
      'handoff_target_type' => 'member', 'response_window' => 'outside_business_hours'
    )
    expect(agent.agent_inboxes.pluck(:id)).to eq([link.id])
  end

  it 'rechecks instruction under the agent lock when the Builder saw a draft first' do
    agent = Autonomia::Agents::Agent.create!(
      account: account, name: 'Nome preservado', agent_type: 'custom', mode: :guided, status: :draft,
      enabled: false, config: { 'voice' => 'feminina' }
    )
    thread = Autonomia::Agents::BuildThread.create!(account: account, agent: agent)
    stale_agent = Autonomia::Agents::Agent.find(agent.id)
    token = thread.begin_build!
    agent.update!(instruction: 'Instrução que chegou antes da escrita')

    attrs = {
      name: 'Nome indevido', agent_type: 'sdr', instruction: 'Nova instrução', scaffold: 'Novo andaime',
      human_card: 'Novo resumo', greeting: 'Nova saudação', fallback_message: 'Novo fallback',
      handoff_rule: 'Nova regra', starter_questions: ['Nova pergunta'], tone: 'Novo tom',
      actuation: 'internal', config: { 'voice' => 'masculina', 'guardrails' => ['Limite novo'] }
    }

    expect(stale_agent.apply_builder_config!(token, attrs)).to be(true)
    expect(stale_agent.reload).to have_attributes(
      name: 'Nome preservado', agent_type: 'custom', greeting: nil, fallback_message: nil, tone: nil,
      actuation: 'external', instruction: 'Nova instrução', handoff_rule: 'Nova regra',
      human_card: 'Novo resumo', scaffold: 'Novo andaime'
    )
    expect(stale_agent.starter_questions).to eq([])
    expect(stale_agent.config).to include('voice' => 'feminina', 'guardrails' => ['Limite novo'])
  end

  it 'refuses a manual switch after enqueue before the writer mutates the agent' do
    agent = Autonomia::Agents::Agent.create!(
      account: account, name: 'Clara', agent_type: 'custom', mode: :guided, status: :draft,
      enabled: false, instruction: 'Instrução guiada', greeting: 'Oi', fallback_message: 'Não sei',
      tone: 'Cordial', config: { 'voice' => 'feminina' }
    )
    thread = Autonomia::Agents::BuildThread.create!(account: account, agent: agent)
    token = thread.begin_build!
    agent.update!(mode: :manual, instruction: 'Instrução escrita pela pessoa')

    builder = Autonomia::Agents::Builder.new(account: account, build_thread: thread.reload)
    client = instance_double(Crm::Ai::ResponsesClient, create: { text: builder_payload.to_json })
    allow(builder).to receive(:client).and_return(client)
    allow(Autonomia::Agents::Builder).to receive(:new).and_return(builder)

    expect do
      Autonomia::Agents::Builder::SubmitJob.perform_now(thread.id, token)
    end.not_to raise_error

    expect(thread.reload).to be_failed
    expect(thread.state.fetch('error')).to eq('manual_mode')
    expect(agent.reload).to have_attributes(
      name: 'Clara', instruction: 'Instrução escrita pela pessoa', greeting: 'Oi',
      fallback_message: 'Não sei', tone: 'Cordial', mode: 'manual'
    )
    expect(agent.config).to include('voice' => 'feminina')
  end
end

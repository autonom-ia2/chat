require 'rails_helper'

# #2490 — o Construtor guarda o canal que o dono pediu (leitura do MODELO, campo canal_pedido do schema) no state da thread,
# para a Confira sugerir só a caixa desse canal. "nenhum" é a saída "não se aplica"; valor fora da lista também vira
# "nenhum". O ajuste da Fase 2 tem schema próprio e fica sem o campo.
RSpec.describe Autonomia::Agents::Builder do
  let(:account) { create(:account) }
  let(:thread) { Autonomia::Agents::BuildThread.create!(account: account) }
  let(:builder) { described_class.new(account: account, build_thread: thread) }
  let(:fake_client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:canal_da_enxuta) { 'nenhum' }
  let(:canal_da_completa) { 'instagram' }
  let(:fechar) { false }
  let(:lean_payload) do
    { 'name' => '', 'agent_type' => 'sdr', 'needs_more_info' => !fechar,
      'next_question' => fechar ? '' : 'Qual o horário de atendimento?', 'user_asked_to_close' => fechar,
      'canal_pedido' => canal_da_enxuta }
  end
  let(:full_payload) do
    {
      'name' => 'Ana', 'agent_type' => 'sdr', 'instruction' => 'Instrução completa da Ana.', 'scaffold' => 'andaime',
      'human_card' => 'A Ana faz a pré-venda da corretora.', 'greeting' => 'Oi!', 'fallback_message' => 'Vou verificar.',
      'handoff_rule' => 'Passa para humano.', 'starter_questions' => [], 'tone' => 'cordial', 'guardrails' => [],
      'voice' => 'feminina', 'needs_more_info' => false, 'next_question' => '', 'user_asked_to_close' => true,
      'canal_pedido' => canal_da_completa
    }
  end

  before do
    allow(builder).to receive(:credential).and_return({ api_key: 'chave-de-teste' })
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(fake_client)
    allow(fake_client).to receive(:create) do |**kwargs|
      lean = kwargs[:input].last[:content].first[:text] == described_class::LEAN_TURN_NOTE
      { text: (lean ? lean_payload : full_payload).to_json, usage: { 'output_tokens' => 100 }, tools_used: [] }
    end
    thread.persist_start_options!(type: 'sdr', with_knowledge: false)
    thread.append_message!('user', 'Quero um agente de pré-venda no Instagram.')
    thread.save!
  end

  def run_turn
    with_modified_env(AI_WEB_SEARCH_ENABLED: 'false') { builder.run!(thread.begin_build!) }
    thread.reload
  end

  it 'asks the model for the channel as a closed list with a way out, in every call' do
    canal = described_class::BUILDER_SCHEMA[:schema][:properties][:canal_pedido]

    expect(canal[:enum]).to eq(%w[whatsapp instagram facebook site email telegram nenhum])
    expect(canal[:description]).to include('nenhum quando nao se aplica')
    expect(described_class::BUILDER_SCHEMA[:schema][:required]).to include('canal_pedido')
    expect(described_class::LEAN_TURN_NOTE).to include('canal_pedido')
  end

  context 'when the interview goes on (lean call)' do
    let(:canal_da_enxuta) { 'whatsapp' }

    it 'keeps the channel the model read in the thread state' do
      expect(run_turn.state['canal_pedido']).to eq('whatsapp')
    end
  end

  context 'when the turn closes the agent (full call)' do
    let(:fechar) { true }

    it 'keeps the reading of the full call, which applies the agent, in the thread and in the agent' do
      expect(run_turn.state['canal_pedido']).to eq('instagram')
      expect(thread.agent.instruction).to eq('Instrução completa da Ana.')
      # Um rascunho reaberto (sem a thread na tela) lê daqui.
      expect(thread.agent.config['canal_pedido']).to eq('instagram')
    end
  end

  context 'when an existing agent is adjusted' do
    let(:canal_da_completa) { 'nenhum' }
    let(:agente) do
      Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'sdr', mode: :guided, status: :active,
                                       enabled: true, instruction: 'Instrução fechada da Ana.',
                                       config: { 'canal_pedido' => 'instagram' })
    end
    let(:thread) { Autonomia::Agents::BuildThread.create!(account: account, agent: agente) }

    it 'keeps the channel asked at creation (the adjustment talk does not mention it)' do
      run_turn
      expect(agente.reload.config['canal_pedido']).to eq('instagram')
    end
  end

  context 'when the model answers a value outside the list' do
    let(:canal_da_enxuta) { 'Instagram da loja' }

    it 'stores "nenhum" so the screen lets the person choose' do
      expect(run_turn.state['canal_pedido']).to eq('nenhum')
    end
  end

  it 'leaves the pilot adjustment schema (Fase 2) without the field' do
    schema = described_class::AjustePorLista::SCHEMA[:schema]

    expect(schema[:properties]).not_to have_key(:canal_pedido)
    expect(schema[:required]).not_to include('canal_pedido')
  end
end

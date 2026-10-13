require 'rails_helper'

# #1367 PR 2 (alavancas 2 + 1). Nos turnos em que o Construtor ainda vai perguntar, a chamada ENXUTA termina com o
# aviso LEAN_TURN_NOTE e desliga a busca (tool_choice 'none'): o modelo não escreve instrução, andaime nem cartão.
# Quando ele indica que vai fechar (ou há sinal determinístico de fechamento), vem a chamada COMPLETA, com a busca, e
# só ela aplica a configuração. As duas mandam o MESMO começo de pedido (instrução, schema, ferramentas, input), para
# a completa aproveitar o cache da enxuta.
RSpec.describe Autonomia::Agents::Builder do
  let(:account) { create(:account) }
  let(:thread) { Autonomia::Agents::BuildThread.create!(account: account) }
  let(:builder) { described_class.new(account: account, build_thread: thread) }
  let(:fake_client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:lean_payload) do
    { 'name' => '', 'agent_type' => 'sdr', 'needs_more_info' => true,
      'next_question' => 'Qual o horário de atendimento?', 'user_asked_to_close' => false }
  end
  let(:full_payload) do
    {
      'name' => 'Ana', 'agent_type' => 'sdr', 'instruction' => 'Instrução completa da Ana.', 'scaffold' => 'andaime',
      'human_card' => 'A Ana faz a pré-venda da corretora.', 'greeting' => 'Oi!', 'fallback_message' => 'Vou verificar.',
      'handoff_rule' => 'Passa para humano.', 'starter_questions' => [], 'tone' => 'cordial', 'guardrails' => [],
      'voice' => 'feminina', 'needs_more_info' => false, 'next_question' => '', 'user_asked_to_close' => false
    }
  end
  let(:calls) { [] }

  before do
    allow(builder).to receive(:credential).and_return({ api_key: 'chave-de-teste' })
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(fake_client)
    allow(fake_client).to receive(:create) do |**kwargs|
      calls << kwargs
      payload = lean_call?(kwargs) ? lean_payload : full_payload
      { text: payload.to_json, usage: { 'output_tokens' => 100 }, tools_used: [] }
    end
    thread.persist_start_options!(type: 'sdr', with_knowledge: false)
    thread.save!
  end

  def lean_call?(call)
    call[:input].last[:content].first[:text] == described_class::LEAN_TURN_NOTE
  end

  def expect_lean_call(call, tool_choice: 'none')
    expect(lean_call?(call)).to be(true)
    expect(call[:schema]).to eq(described_class::BUILDER_SCHEMA)
    expect(call[:tool_choice]).to eq(tool_choice)
  end

  def run_turn(web_search: 'true')
    with_modified_env(AI_WEB_SEARCH_ENABLED: web_search) { builder.run!(thread.begin_build!) }
  end

  def expect_full_call_with_search(call)
    expect(lean_call?(call)).to be(false)
    expect(call[:schema]).to eq(described_class::BUILDER_SCHEMA)
    expect(call[:tools]).to eq(Crm::Ai::WebSearch::TOOL)
    expect(call).not_to have_key(:tool_choice)
  end

  def expect_clients(*features)
    features.each do |feature|
      expect(Crm::Ai::ResponsesClient).to have_received(:new)
        .with(hash_including(feature: feature, cache_key: "agente_builder:#{account.id}"))
    end
  end

  describe 'the lean turn note' do
    it 'tells the model in the mother instruction not to write the instruction in the lean turns' do
      expect(described_class::MOTHER_INSTRUCTION).to include('COLETA ENXUTA')
      expect(described_class::LEAN_TURN_NOTE).to start_with('COLETA ENXUTA')
    end
  end

  context 'when the interview still has a question (coleta)' do
    before { thread.append_message!('user', 'Quero uma SDR para a minha corretora') }

    it 'makes one lean call, with web_search turned off by tool_choice, labeled coleta, and applies nothing' do
      run_turn

      expect(calls.size).to eq(1)
      expect_lean_call(calls.first)
      expect(calls.first[:tools]).to eq(Crm::Ai::WebSearch::TOOL)
      expect_clients('agente_builder_coleta')
      expect(thread.reload.state['needs_more_info']).to be(true)
      expect(thread.state['next_question']).to eq('Qual o horário de atendimento?')
      expect(thread.agent.instruction).to be_blank
    end

    it 'rebuilds the input on the next turn of the same builder' do
      run_turn
      thread.append_message!('user', 'De segunda a sexta')

      run_turn

      expect(calls.last[:input].to_json).to include('De segunda a sexta')
    end
  end

  context 'when the owner says "pode fechar" in a collection turn' do
    let(:lean_payload) { super().merge('needs_more_info' => false, 'next_question' => '', 'user_asked_to_close' => true) }

    before { thread.append_message!('user', 'pode fechar') }

    it 'makes the full call with web_search, labeled fechamento, and applies its configuration' do
      run_turn

      expect(calls.size).to eq(2)
      expect_lean_call(calls.first)
      expect_full_call_with_search(calls.last)
      expect_clients('agente_builder_coleta', 'agente_builder_fechamento')
      expect(thread.reload.state['applied']).to be(true)
      expect(thread.agent.instruction).to eq('Instrução completa da Ana.')
    end

    it 'keeps the close order read by the lean call even if the full call does not repeat it' do
      full_payload.merge!('needs_more_info' => true, 'next_question' => 'E o horário?', 'user_asked_to_close' => false)

      run_turn

      expect(thread.reload.state['applied']).to be(true)
      expect(thread.agent.instruction).to eq('Instrução completa da Ana.')
    end

    it 'does not carry the close order into the next turn of the same builder' do
      run_turn
      lean_payload.merge!('needs_more_info' => true, 'next_question' => 'Algo mais?', 'user_asked_to_close' => false)
      thread.update!(agent: nil)
      calls.clear

      run_turn

      expect(calls.size).to eq(1)
      expect_lean_call(calls.first)
    end

    it 'keeps web_search off in both calls when the global switch is off' do
      run_turn(web_search: 'false')

      expect(calls.size).to eq(2)
      expect_lean_call(calls.first, tool_choice: nil)
      expect(calls.pluck(:tools)).to all(be_nil)
      expect(calls.last[:schema]).to eq(described_class::BUILDER_SCHEMA)
    end
  end

  context 'when the model closes on its own (fechamento natural)' do
    let(:lean_payload) { super().merge('needs_more_info' => false, 'next_question' => '') }

    before { thread.append_message!('user', 'De segunda a sexta, das 9h às 18h') }

    it 'makes the full call with web_search and applies its configuration' do
      run_turn

      expect(calls.size).to eq(2)
      expect_full_call_with_search(calls.last)
      expect(thread.reload.agent.instruction).to eq('Instrução completa da Ana.')
    end
  end

  context 'when the close is forced over a stubborn question (forced_close)' do
    let(:lean_payload) { super().merge('user_asked_to_close' => true) }

    before do
      thread.append_message!('user', 'chega de pergunta, monta do jeito que está')
      full_payload.merge!('needs_more_info' => true, 'next_question' => 'Qual o horário de atendimento?')
      allow(Rails.logger).to receive(:info)
    end

    it 'applies the instruction written by the full call and logs the two calls' do
      run_turn

      expect(calls.size).to eq(2)
      expect_full_call_with_search(calls.last)
      expect(thread.reload.state['applied']).to be(true)
      expect(thread.agent.instruction).to eq('Instrução completa da Ana.')
      expect(thread.agent.human_card).to include('Qual o horário de atendimento?')
      expect(Rails.logger).to have_received(:info).with(
        a_string_including('phase=fechamento', 'calls=2', 'web_search_offered=true', 'fechou=true', 'forced_close=true')
      )
    end
  end

  context 'when a deterministic signal already closes the turn before any call' do
    before do
      thread.update!(no_materials_declared: true)
      thread.append_message!('user', 'Não tenho material')
      allow(Rails.logger).to receive(:info)
    end

    it 'skips the lean call and makes only the full call with web_search' do
      run_turn

      expect(calls.size).to eq(1)
      expect_full_call_with_search(calls.first)
      expect_clients('agente_builder_fechamento')
      expect(thread.reload.agent.instruction).to eq('Instrução completa da Ana.')
      expect(Rails.logger).to have_received(:info).with(a_string_including('phase=fechamento', 'calls=1'))
    end
  end

  context 'when the materials gate would hold a natural close' do
    let(:lean_payload) { super().merge('needs_more_info' => false, 'next_question' => '') }

    before do
      draft = Autonomia::Agents::Agent.create!(account: account, name: 'Novo agente', agent_type: 'sdr', mode: :guided,
                                               status: :draft, enabled: false)
      thread.update!(agent: draft)
      thread.append_message!('user', 'Quero uma SDR')
      Autonomia::Agents::Source.create!(account: account, agent: draft, source_type: 'txt',
                                        status: :ready, review_status: 'needs_resend')
    end

    it 'does not spend the full call and keeps the review question' do
      run_turn

      expect(calls.size).to eq(1)
      expect(thread.reload.state['needs_more_info']).to be(true)
      expect(thread.state['applied']).to be(false)
    end
  end

  context 'when the agent already exists (ajuste)' do
    let(:agent) do
      Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'sdr', mode: :guided,
                                       status: :active, enabled: true, instruction: 'Instrução fechada da Ana.')
    end

    before do
      thread.update!(agent: agent)
      thread.append_message!('user', 'Troque a saudação para "Olá, aqui é a Ana"')
    end

    # Decisão do gestor (#1367): o "Mudar conversando" é o uso do dia a dia e não pode ficar mais lento. O ajuste
    # segue com UMA chamada completa, com busca, como antes deste PR, inclusive quando a resposta é uma pergunta.
    context 'with a clear request' do
      it 'makes a single full call with web_search, labeled ajuste, and applies it' do
        run_turn

        expect(calls.size).to eq(1)
        expect_full_call_with_search(calls.first)
        expect_clients('agente_builder_ajuste')
        expect(Crm::Ai::ResponsesClient).not_to have_received(:new).with(hash_including(feature: 'agente_builder_coleta'))
        expect(Crm::Ai::ResponsesClient).not_to have_received(:new).with(hash_including(feature: 'agente_builder_fechamento'))
        expect(agent.reload.instruction).to eq('Instrução completa da Ana.')
      end
    end

    context 'with a clarifying question' do
      before { full_payload.merge!('needs_more_info' => true, 'next_question' => 'Substitui a saudação atual?') }

      it 'still makes a single full call with web_search and keeps the instruction' do
        run_turn

        expect(calls.size).to eq(1)
        expect_full_call_with_search(calls.first)
        expect(thread.reload.state['needs_more_info']).to be(true)
        expect(thread.state['next_question']).to eq('Substitui a saudação atual?')
        expect(agent.reload.instruction).to eq('Instrução fechada da Ana.')
      end
    end

    it 'puts the stable current configuration before the volatile blocks of the prompt' do
      thread.update!(state: thread.state.to_h.merge('pending_question' => 'Substitui a saudação atual?'))
      blocks = builder.send(:context_blocks)
      adjust_index = blocks.index { |b| b.include?('MODO AJUSTE') }
      pending_index = blocks.index { |b| b.include?('PERGUNTA PENDENTE') }
      materials_index = blocks.index { |b| b.include?('STATUS DOS MATERIAIS') }

      expect(adjust_index).to be < pending_index
      expect(adjust_index).to be < materials_index
    end
  end

  describe 'reasoning' do
    let(:lean_payload) { super().merge('needs_more_info' => false, 'next_question' => '') }

    before { thread.append_message!('user', 'De segunda a sexta') }

    it 'keeps the builder model at medium in both calls' do
      run_turn

      expect(calls.size).to eq(2)
      expect(calls.pluck(:reasoning_effort)).to all(eq('medium'))
      expect(calls.pluck(:model)).to all(eq(Autonomia::Agents::Config::BUILDER_MODEL))
    end
  end

  # Rodada 1 do A/B do #1367: com schema e ferramentas diferentes na enxuta, a completa do fechamento teve 0% de
  # cache. A OpenAI põe ferramentas e schema no prefixo em cache; a enxuta só pode diferir DEPOIS do input comum.
  describe 'cache prefix shared by the two calls' do
    let(:lean_payload) { super().merge('needs_more_info' => false, 'next_question' => '') }

    before { thread.append_message!('user', 'De segunda a sexta') }

    it 'sends the same instructions, schema, tools and input, with the lean note only at the end' do
      run_turn
      lean, full = calls

      %i[instructions schema tools reasoning_effort].each { |key| expect(lean[key]).to eq(full[key]) }
      expect(lean[:input][0...-1]).to eq(full[:input])
      expect(lean[:input].last).to eq(role: 'developer', content: [{ type: 'input_text', text: described_class::LEAN_TURN_NOTE }])
    end
  end
end

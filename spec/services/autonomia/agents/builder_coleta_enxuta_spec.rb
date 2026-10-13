require 'rails_helper'

# #1367 PR 2 (alavancas 2 + 1). Nos turnos em que o Construtor ainda vai perguntar, a chamada pede só o schema
# ENXUTO, sem busca na web: o modelo não escreve instrução, andaime nem cartão. Quando ele indica que vai fechar
# (ou há sinal determinístico de fechamento), vem a chamada COMPLETA, com a busca, e só ela aplica a configuração.
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
      payload = kwargs[:schema] == described_class::LEAN_SCHEMA ? lean_payload : full_payload
      { text: payload.to_json, usage: { 'output_tokens' => 100 }, tools_used: [] }
    end
    thread.persist_start_options!(type: 'sdr', with_knowledge: false)
    thread.save!
  end

  def run_turn(web_search: 'true')
    with_modified_env(AI_WEB_SEARCH_ENABLED: web_search) { builder.run!(thread.begin_build!) }
  end

  def expect_full_call_with_search(call)
    expect(call[:schema]).to eq(described_class::BUILDER_SCHEMA)
    expect(call[:tools]).to eq(Crm::Ai::WebSearch::TOOL)
  end

  def expect_clients(*features)
    features.each do |feature|
      expect(Crm::Ai::ResponsesClient).to have_received(:new)
        .with(hash_including(feature: feature, cache_key: "agente_builder:#{account.id}"))
    end
  end

  describe 'the lean schema' do
    it 'carries only what the question needs, with the model close reading' do
      properties = described_class::LEAN_SCHEMA[:schema][:properties]

      expect(properties.keys).to contain_exactly(:name, :agent_type, :needs_more_info, :next_question,
                                                 :user_asked_to_close)
      expect(described_class::LEAN_SCHEMA[:schema][:required]).to match_array(properties.keys.map(&:to_s))
      expect(properties[:user_asked_to_close][:description]).to eq(described_class::USER_ASKED_TO_CLOSE_DESCRIPTION)
    end

    it 'tells the model in the mother instruction not to write the instruction in the lean turns' do
      expect(described_class::MOTHER_INSTRUCTION).to include('COLETA ENXUTA')
    end
  end

  context 'when the interview still has a question (coleta)' do
    before { thread.append_message!('user', 'Quero uma SDR para a minha corretora') }

    it 'makes one lean call, without web_search, labeled coleta, and applies nothing' do
      run_turn

      expect(calls.size).to eq(1)
      expect(calls.first[:schema]).to eq(described_class::LEAN_SCHEMA)
      expect(calls.first[:tools]).to be_nil
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
      expect(calls.first[:schema]).to eq(described_class::LEAN_SCHEMA)
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
      expect(calls.first[:schema]).to eq(described_class::LEAN_SCHEMA)
    end

    it 'keeps web_search off in the full call when the global switch is off' do
      run_turn(web_search: 'false')

      expect(calls.size).to eq(2)
      expect(calls.last[:schema]).to eq(described_class::BUILDER_SCHEMA)
      expect(calls.last[:tools]).to be_nil
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

    context 'with a clear request' do
      let(:lean_payload) { super().merge('needs_more_info' => false, 'next_question' => '') }

      it 'closes with the full call and web_search, both labeled ajuste' do
        run_turn

        expect(calls.size).to eq(2)
        expect(calls.first[:schema]).to eq(described_class::LEAN_SCHEMA)
        expect_full_call_with_search(calls.last)
        expect_clients('agente_builder_ajuste')
        expect(Crm::Ai::ResponsesClient).not_to have_received(:new).with(hash_including(feature: 'agente_builder_fechamento'))
        expect(agent.reload.instruction).to eq('Instrução completa da Ana.')
      end
    end

    context 'with a clarifying question' do
      it 'answers with the lean call only and keeps the instruction' do
        run_turn

        expect(calls.size).to eq(1)
        expect(calls.first[:tools]).to be_nil
        expect(thread.reload.state['needs_more_info']).to be(true)
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
      expect(calls.pluck(:instructions)).to all(eq(described_class::MOTHER_INSTRUCTION))
      expect(calls.first[:input]).to eq(calls.last[:input])
    end
  end
end

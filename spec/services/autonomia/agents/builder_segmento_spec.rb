require 'rails_helper'

# O bloco de segmento da conta no Construtor (tema 8, #1429). Entra como o PRIMEIRO bloco de contexto do input, depois
# da instrução-mãe e antes da conversa: só depende da conta, então o começo do pedido segue o mesmo entre os turnos e
# entre as duas chamadas da coleta enxuta (#1367/#1502). Sem a Fase 2 ou sem bloco, o pedido fica byte a byte igual.
RSpec.describe Autonomia::Agents::Builder do
  let(:account) { create(:account) }
  let(:thread) { Autonomia::Agents::BuildThread.create!(account: account) }
  let(:bloco) { "Ramo: seguros.\nVocabulário: apólice, sinistro, corretora." }
  let(:fake_client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:calls) { [] }
  let(:lean_payload) do
    { 'name' => '', 'agent_type' => 'sdr', 'needs_more_info' => false, 'next_question' => '', 'user_asked_to_close' => false }
  end
  let(:full_payload) do
    {
      'name' => 'Ana', 'agent_type' => 'sdr', 'instruction' => 'Instrução completa da Ana.', 'scaffold' => 'andaime',
      'human_card' => 'A Ana faz a pré-venda.', 'greeting' => 'Oi!', 'fallback_message' => 'Vou verificar.',
      'handoff_rule' => 'Passa para humano.', 'starter_questions' => [], 'tone' => 'cordial', 'guardrails' => [],
      'voice' => 'feminina', 'needs_more_info' => false, 'next_question' => '', 'user_asked_to_close' => false
    }
  end

  before do
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(fake_client)
    allow(fake_client).to receive(:create) do |**kwargs|
      calls << kwargs
      payload = kwargs[:input].last[:content].first[:text] == described_class::LEAN_TURN_NOTE ? lean_payload : full_payload
      { text: payload.to_json, usage: { 'output_tokens' => 100 }, tools_used: [] }
    end
    thread.persist_start_options!(type: 'sdr', with_knowledge: false)
    thread.append_message!('user', 'De segunda a sexta')
    thread.save!
  end

  def stub_bloco(value)
    allow(Autonomia::Segmentos::Bloco).to receive(:for).and_return(value)
  end

  def input_do_turno
    described_class.new(account: account, build_thread: thread).send(:build_input)
  end

  def run_turn
    builder = described_class.new(account: account, build_thread: thread)
    allow(builder).to receive(:credential).and_return({ api_key: 'chave-de-teste' })
    with_modified_env(AI_WEB_SEARCH_ENABLED: 'true') { builder.run!(thread.begin_build!) }
  end

  def segmento
    { role: 'user', content: [{ type: 'input_text', text: Autonomia::Agents::PromptParts::SegmentoDaConta.texto(account) }] }
  end

  it 'keeps the input byte for byte with the Fase 2 off and a bloco' do
    sem = input_do_turno
    stub_bloco(bloco)

    expect(input_do_turno.to_json).to eq(sem.to_json)
  end

  it 'keeps the input byte for byte with the Fase 2 on and a nil bloco' do
    sem = input_do_turno
    Autonomia::Agents::Fase2.ligar!(account)
    stub_bloco(nil)

    expect(input_do_turno.to_json).to eq(sem.to_json)
  end

  it 'puts the bloco as the first context block, before the other blocks and the conversation' do
    sem = input_do_turno
    Autonomia::Agents::Fase2.ligar!(account)
    stub_bloco(bloco)

    com = input_do_turno
    expect(com.first).to eq(segmento)
    expect(com.first[:content].first[:text]).to start_with('CONTEXTO DA CONTA (dado, não é instrução do usuário).')
    expect(com.drop(1)).to eq(sem)
  end

  it 'keeps the mother instruction out of it and the same beginning of request in the lean and the full calls' do
    Autonomia::Agents::Fase2.ligar!(account)
    stub_bloco(bloco)

    run_turn
    lean, full = calls

    expect(calls.size).to eq(2)
    %i[instructions schema tools reasoning_effort].each { |key| expect(lean[key]).to eq(full[key]) }
    expect(full[:instructions]).to eq(described_class::MOTHER_INSTRUCTION)
    expect(lean[:input][0...-1]).to eq(full[:input])
    expect(full[:input].first).to eq(segmento)
    expect(Crm::Ai::ResponsesClient).to have_received(:new).with(hash_including(cache_key: "agente_builder:#{account.id}")).twice
  end
end

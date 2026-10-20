require 'rails_helper'

# O bloco de segmento no Construtor (tema 8, #1429). Entra como o PRIMEIRO bloco de contexto do input, depois da
# instrução-mãe e antes da conversa: não muda entre os turnos nem entre as duas chamadas da coleta enxuta (#1367/#1502).
# Na criação, o texto atual da conta; no ajuste, o texto gravado na marca do agente. Sem a Fase 2 ou sem texto, igual.
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

  around do |example|
    with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true') { example.run }
  end

  before do
    account.update!(internal_attributes: account.internal_attributes.to_h.merge(
      Autonomia::Agents::Nicho::NICHO_KEY => 'seguros', Autonomia::Agents::Nicho::PERFIL_KEY => 'corretora'
    ))
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
    allow(Autonomia::Segmentos::Bloco).to receive(:for_segmento).and_return(value)
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
    { role: 'user', content: [{ type: 'input_text', text: Autonomia::Agents::PromptParts::SegmentoDaConta.texto(account, bloco) }] }
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

  # MARCA DE BASE (#1429): o agente grava o segmento, a versão e o texto com que nasceu; o ajuste usa o texto gravado.
  describe 'marca de base' do
    def trocar_perfil(perfil)
      account.update!(internal_attributes: account.internal_attributes.to_h.merge(Autonomia::Agents::Nicho::PERFIL_KEY => perfil))
    end

    def stub_bloco_por_segmento(prefixo = 'BLOCO')
      allow(Autonomia::Segmentos::Bloco).to receive(:for_segmento) { |seg| seg && "#{prefixo} #{seg}" }
      allow(Autonomia::Segmentos::Bloco).to receive(:versao) { |seg| seg && "v-#{prefixo}" }
    end

    def textos(input)
      input.flat_map { |item| item[:content].map { |parte| parte[:text] } }.join("\n")
    end

    def thread_de_ajuste(agente)
      Autonomia::Agents::BuildThread.create!(account: account, agent: agente).tap do |ajuste|
        ajuste.append_message!('user', 'Deixe o tom mais formal')
        ajuste.save!
      end
    end

    def agente_existente(config)
      Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'sdr', status: :active, enabled: true,
                                       instruction: 'Instrução da Ana.', config: config)
    end

    def input_do_ajuste(agente)
      described_class.new(account: account, build_thread: thread_de_ajuste(agente)).send(:build_input)
    end

    it 'grava segmento, versão e texto vigentes no agente que nasce pelo Construtor com a Fase 2' do
      Autonomia::Agents::Fase2.ligar!(account)
      stub_bloco_por_segmento

      run_turn

      expect(thread.reload.agent.config['base']).to eq(
        'segmento' => 'seguros/corretora', 'versao' => 'v-BLOCO', 'texto' => 'BLOCO seguros/corretora'
      )
    end

    it 'hoje (stubs reais) grava o segmento com versão e texto nil' do
      Autonomia::Agents::Fase2.ligar!(account)

      run_turn

      expect(thread.reload.agent.config['base']).to eq('segmento' => 'seguros/corretora', 'versao' => nil, 'texto' => nil)
    end

    it 'grava segmento nil na conta geral (nasceu sem base)' do
      Autonomia::Agents::Fase2.ligar!(account)
      account.update!(internal_attributes: account.internal_attributes.to_h.merge(Autonomia::Agents::Nicho::NICHO_KEY => 'geral'))
      stub_bloco_por_segmento

      run_turn

      expect(thread.reload.agent.config['base']).to eq('segmento' => nil, 'versao' => nil, 'texto' => nil)
    end

    it 'não grava marca quando a leitura do segmento falha (o agente nasce sem base, não como conta geral)' do
      Autonomia::Agents::Fase2.ligar!(account)
      allow(Autonomia::Agents::Nicho).to receive(:for).and_raise(ArgumentError)

      run_turn

      expect(thread.reload.agent.config).not_to have_key('base')
    end

    it 'com rascunho já marcado, usa o texto gravado nele, não o atual' do
      Autonomia::Agents::Fase2.ligar!(account)
      rascunho = Autonomia::Agents::Agent.create!(account: account, name: 'Novo agente', agent_type: 'sdr', status: :draft,
                                                  config: { 'base' => { 'segmento' => 'seguros/corretora', 'versao' => 'v1',
                                                                        'texto' => 'TEXTO GRAVADO' } })
      thread.update!(agent: rascunho)
      stub_bloco_por_segmento('NOVO')

      input = input_do_turno

      expect(input.first[:content].first[:text]).to end_with('TEXTO GRAVADO')
      expect(textos(input)).not_to include('NOVO')
    end

    it 'não grava marca sem a Fase 2' do
      run_turn

      expect(thread.reload.agent.config).not_to have_key('base')
    end

    it 'na criação usa o texto atual do segmento da conta' do
      Autonomia::Agents::Fase2.ligar!(account)
      stub_bloco_por_segmento

      expect(input_do_turno.first[:content].first[:text]).to end_with('BLOCO seguros/corretora')
    end

    it 'no ajuste usa o texto gravado, não o atual nem o da conta trocada' do
      Autonomia::Agents::Fase2.ligar!(account)
      agente = agente_existente('with_knowledge' => false,
                                'base' => { 'segmento' => 'seguros/corretora', 'versao' => 'v1', 'texto' => 'TEXTO GRAVADO' })
      trocar_perfil('seguradora')
      stub_bloco_por_segmento('NOVO')

      input = input_do_ajuste(agente)

      expect(input.first[:content].first[:text]).to end_with('TEXTO GRAVADO')
      expect(textos(input)).not_to include('NOVO')
    end

    it 'no ajuste de agente com marca sem texto não manda bloco' do
      Autonomia::Agents::Fase2.ligar!(account)
      agente = agente_existente('with_knowledge' => false, 'base' => { 'segmento' => 'seguros/corretora', 'versao' => nil, 'texto' => nil })
      stub_bloco_por_segmento

      expect(textos(input_do_ajuste(agente))).not_to include('BLOCO')
    end

    it 'no ajuste de agente sem marca não manda bloco, mesmo com a conta em seguros' do
      Autonomia::Agents::Fase2.ligar!(account)
      stub_bloco_por_segmento

      expect(textos(input_do_ajuste(agente_existente('with_knowledge' => false)))).not_to include('BLOCO')
    end
  end
end

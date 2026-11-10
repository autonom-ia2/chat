require 'rails_helper'

# #2858 F3 — o agente já nasce com as ferramentas prontas. O Construtor recebe como DADO as prontas liberadas para a
# conta e escolhe, no campo ferramentas_prontas do schema, as que o agente precisa (lista vazia = nenhuma combina). O
# código só filtra pelo que a conta tem liberado. Sem a flag do Construtor, nada vai ao modelo e nada é guardado. O
# modelo é dublado: nenhuma chamada paga.
RSpec.describe Autonomia::Agents::Builder do
  include FerramentasProntasHelper

  let(:account) { create(:account) }
  let(:thread) { Autonomia::Agents::BuildThread.create!(account: account) }
  let(:builder) { described_class.new(account: account, build_thread: thread) }
  let(:fake_client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:escolhidas) { %w[fipe cep cpf] }
  let(:entradas) { [] }
  let(:full_payload) do
    {
      'name' => 'Ana', 'agent_type' => 'sdr', 'instruction' => 'Instrução completa da Ana.', 'scaffold' => 'andaime',
      'human_card' => 'A Ana cota seguro auto.', 'greeting' => 'Oi!', 'fallback_message' => 'Vou verificar.',
      'handoff_rule' => 'Passa para humano.', 'starter_questions' => [], 'tone' => 'cordial', 'guardrails' => [],
      'voice' => 'feminina', 'needs_more_info' => false, 'next_question' => '', 'user_asked_to_close' => true,
      'canal_pedido' => 'nenhum', 'ferramentas_prontas' => escolhidas
    }
  end

  def ligar_construtor
    ligar_consultas(account)
    account.enable_features!(Autonomia::FerramentasProntas::FLAG_VITRINE, Autonomia::FerramentasProntas::FLAG_CONSTRUTOR)
  end

  def run_turn
    with_modified_env(AI_WEB_SEARCH_ENABLED: 'false') { builder.run!(thread.begin_build!) }
    thread.reload
  end

  def contexto_enviado
    entradas.flat_map { |entrada| entrada.flat_map { |item| Array(item[:content]).pluck(:text) } }.compact
            .find { |texto| texto.start_with?('FERRAMENTAS PRONTAS') }
  end

  before do
    allow(builder).to receive(:credential).and_return({ api_key: 'chave-de-teste' })
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(fake_client)
    allow(fake_client).to receive(:create) do |**kwargs|
      entradas << kwargs[:input]
      { text: full_payload.to_json, usage: { 'output_tokens' => 100 }, tools_used: [] }
    end
    thread.persist_start_options!(type: 'sdr', with_knowledge: false)
    thread.append_message!('user', 'Quero um agente que cota seguro auto. Pode criar.')
    thread.save!
  end

  it 'asks every call for a closed list of catalog keys, with "none fits" as the empty list' do
    campo = described_class::BUILDER_SCHEMA[:schema][:properties][:ferramentas_prontas]

    expect(campo[:items][:enum]).to match_array(Autonomia::FerramentasProntas::Catalogo.chaves)
    expect(campo[:description]).to include('Lista vazia quando nenhuma combina')
    expect(described_class::BUILDER_SCHEMA[:schema][:required]).to include('ferramentas_prontas')
    expect(described_class::LEAN_TURN_NOTE).to include('ferramentas_prontas como lista vazia')
  end

  context 'with the Construtor flag on' do
    before { ligar_construtor }

    it 'sends the released tools as data and keeps the chosen ones in the thread and in the agent' do
      run_turn

      expect(contexto_enviado).to include('- fipe: Valor do carro (FIPE).', '- cep:', '- bancos:')
      expect(thread.state['ferramentas_sugeridas']).to eq(%w[cep fipe cpf])
      expect(thread.agent.config['ferramentas_sugeridas']).to eq(%w[cep fipe cpf])
      expect(thread.agent.tools).to be_empty # quem inclui é a Confira, com a pessoa real
    end

    context 'when the model says none fits' do
      let(:escolhidas) { [] }

      it 'keeps an empty list' do
        expect(run_turn.state['ferramentas_sugeridas']).to eq([])
      end
    end

    context 'when the model picks a tool the account does not have' do
      let(:escolhidas) { %w[fipe cpf inventada] }

      before { account.disable_features!(Autonomia::FerramentasProntas::FLAG_CONSULTAS) }

      it 'keeps only the released ones' do
        expect(run_turn.state['ferramentas_sugeridas']).to eq(%w[fipe])
      end
    end
  end

  context 'with the Construtor flag off' do
    before do
      ligar_consultas(account)
      account.enable_features!(Autonomia::FerramentasProntas::FLAG_VITRINE)
    end

    it 'sends no tool block and keeps nothing' do
      run_turn

      expect(contexto_enviado).to be_nil
      expect(thread.state['ferramentas_sugeridas']).to eq([])
      expect(thread.agent.config['ferramentas_sugeridas']).to eq([])
    end
  end

  context 'when an existing agent is adjusted' do
    let(:agente) do
      Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'sdr', mode: :guided, status: :active,
                                       enabled: true, instruction: 'Instrução fechada da Ana.',
                                       config: { 'ferramentas_sugeridas' => %w[cep] })
    end
    let(:thread) { Autonomia::Agents::BuildThread.create!(account: account, agent: agente) }

    before { ligar_construtor }

    it 'does not offer tools again nor touch what the creation chose' do
      run_turn

      expect(contexto_enviado).to be_nil
      expect(thread.state).not_to have_key('ferramentas_sugeridas')
      expect(agente.reload.config['ferramentas_sugeridas']).to eq(%w[cep])
    end
  end
end

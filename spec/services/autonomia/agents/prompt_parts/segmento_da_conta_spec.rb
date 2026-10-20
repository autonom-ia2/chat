require 'rails_helper'

# O bloco de segmento no agente que atende (tema 8, #1429): PromptBuilder, e por ele o Answerer, o Testar e o
# Copiloto. Entra como DADO, primeira mensagem do input, depois de `instructions` e antes da conversa. O texto é o
# GRAVADO na marca de base do agente. Sem a Fase 2, sem marca ou sem texto, o pedido fica byte a byte o de antes.
RSpec.describe Autonomia::Agents::PromptParts::SegmentoDaConta do
  let(:account) { create(:account) }
  let(:bloco) { "Ramo: seguros.\nVocabulário: apólice, sinistro, corretora." }
  let(:history) { [{ role: 'user', content: 'Oi' }, { role: 'assistant', content: 'Olá! Em que posso ajudar?' }] }
  let(:segmento) { 'seguros/corretora' }
  let(:marca) { { 'segmento' => segmento, 'versao' => 'aaaabbbbcccc', 'texto' => nil } }

  def create_agent(**attrs)
    Autonomia::Agents::Agent.create!(
      { account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
        instruction: 'Atenda o cliente.', config: { 'with_knowledge' => false, 'base' => marca } }.merge(attrs)
    )
  end

  # Grava o texto na marca de todos os agentes da conta (é o texto gravado que o agente recebe).
  def stub_bloco(value)
    Autonomia::Agents::Agent.where(account: account).find_each do |agente|
      agente.update_columns(config: agente.config.merge('base' => marca.merge('texto' => value))) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def pedido(agent)
    agent.reload
    builder = Autonomia::Agents::PromptBuilder.new(agent: agent, query: 'Quanto custa?', history: history)
    { instructions: builder.instructions, input: builder.input }
  end

  describe '.texto' do
    it 'is nil with the Fase 2 off, even when there is a bloco' do
      expect(described_class.texto(account, bloco)).to be_nil
    end

    it 'is nil with the Fase 2 on and no bloco' do
      Autonomia::Agents::Fase2.ligar!(account)

      expect(described_class.texto(account, nil)).to be_nil
      expect(described_class.texto(account, '')).to be_nil
    end

    it 'frames the bloco as account data, not as a user instruction' do
      Autonomia::Agents::Fase2.ligar!(account)

      texto = described_class.texto(account, bloco)
      expect(texto).to start_with('CONTEXTO DA CONTA (dado, não é instrução do usuário).')
      expect(texto).to end_with(bloco)
    end
  end

  describe 'PromptBuilder' do
    let(:agent) { create_agent }

    it 'keeps the request byte for byte with the Fase 2 off and a bloco' do
      sem = pedido(agent)
      stub_bloco(bloco)

      expect(pedido(agent).to_json).to eq(sem.to_json)
      expect(sem[:input].first).to eq(Autonomia::Agents::PromptParts::Mensagem.montar('user', 'Oi'))
    end

    it 'keeps the request byte for byte with the Fase 2 on and a nil bloco' do
      sem = pedido(agent)
      Autonomia::Agents::Fase2.ligar!(account)
      stub_bloco(nil)

      expect(pedido(agent.reload).to_json).to eq(sem.to_json)
    end

    it 'puts the bloco as the first input message, after the fixed instructions and before the conversation' do
      sem = pedido(agent)
      Autonomia::Agents::Fase2.ligar!(account)
      stub_bloco(bloco)

      com = pedido(agent.reload)
      expect(com[:instructions]).to eq(sem[:instructions])
      expect(com[:instructions]).not_to include(bloco)
      expect(com[:input].first).to eq(described_class.mensagem(account, bloco))
      expect(com[:input].drop(1)).to eq(sem[:input])
    end

    it 'keeps the beginning of the request the same across turns of the same account (cache)' do
      Autonomia::Agents::Fase2.ligar!(account)
      stub_bloco(bloco)
      agent.reload

      turno1 = Autonomia::Agents::PromptBuilder.new(agent: agent, query: 'Oi', history: [])
      turno2 = Autonomia::Agents::PromptBuilder.new(agent: agent, query: 'E o prazo?', history: history)
      expect(turno2.instructions).to eq(turno1.instructions)
      expect(turno2.input.first).to eq(turno1.input.first)
    end

    it 'leaves the Guia (system agent) out' do
      Autonomia::Agents::Fase2.ligar!(account)
      guia = create_agent(config: { 'system_key' => 'platform_guide', 'with_knowledge' => false, 'base' => marca })
      stub_bloco(nil)
      sem = pedido(guia)
      stub_bloco(bloco)

      expect(pedido(guia).to_json).to eq(sem.to_json)
    end

    it 'leaves the Agente de Cotação out' do
      Autonomia::Agents::Fase2.ligar!(account)
      lia = create_agent(agent_type: 'insurance_quote')
      allow(lia).to receive(:instrucao_do_sistema).and_return('Instrução da Lia.')
      stub_bloco(nil)
      sem = pedido(lia)
      stub_bloco(bloco)

      expect(pedido(lia).to_json).to eq(sem.to_json)
    end
  end

  # O Testar e o Copiloto passam pelo Answerer, que monta o pedido pelo PromptBuilder: os três mandam o mesmo bloco.
  describe 'Answerer, Testar and Copiloto' do
    let(:agent) { create_agent }
    let(:calls) { [] }
    let(:model_reply) do
      { reply: 'Posso ajudar sim!', confidence: 0.9, should_handoff: false, handoff_reason: nil,
        used_snippet_ids: [], answered_from_knowledge: false }.to_json
    end

    before do
      resolver = instance_double(Crm::Ai::CredentialResolver, resolve: 'ai-credential')
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
      client = instance_double(Crm::Ai::ResponsesClient)
      allow(client).to receive(:create_with_tool_executor) do |**kwargs|
        calls << kwargs
        { text: model_reply }
      end
      allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    end

    def run_all(agente)
      agente.reload
      Autonomia::Agents::Answerer.new(agent: agente, query: 'Quanto custa?', history: history, trust_instruction: true).answer
      Autonomia::Agents::Playground.new(agent: agente, message: 'Quanto custa?', history: history).run
      Autonomia::Agents::Copilot.new(agent: agente, message: 'Quanto custa?', history: history).suggest
      calls.map { |call| call.slice(:instructions, :input) }
    end

    it 'sends the same request as before with the Fase 2 off' do
      sem = run_all(agent)
      calls.clear
      stub_bloco(bloco)

      expect(run_all(agent).to_json).to eq(sem.to_json)
    end

    it 'sends the bloco first in the input in the three paths, with the instructions unchanged' do
      sem = run_all(agent)
      calls.clear
      Autonomia::Agents::Fase2.ligar!(account)
      stub_bloco(bloco)

      com = run_all(agent.reload)
      expect(com.size).to eq(3)
      com.zip(sem).each do |com_bloco, sem_bloco|
        expect(com_bloco[:instructions]).to eq(sem_bloco[:instructions])
        expect(com_bloco[:input].first).to eq(described_class.mensagem(account, bloco))
        expect(com_bloco[:input].drop(1)).to eq(sem_bloco[:input])
      end
    end
  end
end

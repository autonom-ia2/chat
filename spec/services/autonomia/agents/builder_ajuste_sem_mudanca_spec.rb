require 'rails_helper'

# #2984 — o "Mudar conversando" nas contas fora da Fase 2 dos agentes: o ajuste que não muda nada no agente não fecha
# como aplicado. Antes o turno terminava com `applied: true` e a tela mostrava "Pronto" para um pedido que não entrou.
RSpec.describe Autonomia::Agents::Builder do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Hubber', agent_type: 'support', mode: :guided, status: :active, enabled: true,
      instruction: 'Atenda o cliente da corretora com cordialidade.', scaffold: 'andaime', tone: 'cordial',
      greeting: 'Oi! Aqui é o Hubber.', fallback_message: 'Vou confirmar com a equipe.',
      handoff_rule: 'Passe para a equipe quando o cliente pedir.', starter_questions: ['Como funciona?'],
      human_card: 'O Hubber atende os clientes.', config: { 'guardrails' => ['Não invente valores.'], 'voice' => 'masculina',
                                                            'with_knowledge' => false }
    )
  end
  let(:thread) { Autonomia::Agents::BuildThread.create!(account: account, agent: agent) }
  let(:builder) { described_class.new(account: account, build_thread: thread) }
  let(:estado) { thread.reload.state }
  let(:sem_pedido) do
    I18n.t('autonomia.agents.ajuste.sem_pedido', locale: Autonomia::Agents::Builder::TextosDoAjuste.idioma(nil, account))
  end

  # A saída do Construtor no ajuste: o agente como está, com o que o teste mudar por cima.
  def saida(overrides = {})
    { 'name' => 'Hubber', 'agent_type' => 'support', 'instruction' => 'Atenda o cliente da corretora com cordialidade.',
      'scaffold' => 'andaime', 'human_card' => 'O Hubber atende os clientes.', 'greeting' => 'Oi! Aqui é o Hubber.',
      'fallback_message' => 'Vou confirmar com a equipe.', 'handoff_rule' => 'Passe para a equipe quando o cliente pedir.',
      'starter_questions' => ['Como funciona?'], 'tone' => 'cordial', 'guardrails' => ['Não invente valores.'],
      'voice' => 'masculina', 'needs_more_info' => false, 'next_question' => '', 'user_asked_to_close' => false }.merge(overrides)
  end

  def rodar(parsed)
    fake_client = instance_double(Crm::Ai::ResponsesClient, create: { text: parsed.to_json })
    allow(builder).to receive(:client).and_return(fake_client)
    thread.append_message!('user', 'Tire a pergunta sobre o valor da garantia.')
    builder.run!(thread.begin_build!)
  end

  it 'está fora da Fase 2 dos agentes' do
    expect(Autonomia::Agents::Fase2.ligada?(account)).to be(false)
  end

  describe 'quando o Construtor devolve o agente igual ao que já era' do
    before { rodar(saida) }

    it 'não fecha como aplicado e deixa a conversa aberta' do
      expect(thread.reload).to be_ready
      expect(estado).to include('applied' => false, 'needs_more_info' => true, 'next_question' => sem_pedido)
    end

    it 'responde ao dono com o texto fixo, nunca com um texto do modelo' do
      ultima = Array(thread.reload.messages).last

      expect(ultima).to include('role' => 'assistant', 'content' => sem_pedido)
    end

    it 'deixa o agente como estava' do
      expect(agent.reload).to have_attributes(tone: 'cordial', instruction: 'Atenda o cliente da corretora com cordialidade.',
                                              name: 'Hubber')
    end
  end

  describe 'quando o Construtor muda algo no agente' do
    before { rodar(saida('tone' => 'cordial e curto')) }

    it 'fecha como aplicado, sem pergunta' do
      expect(estado).to include('applied' => true, 'needs_more_info' => false)
      expect(agent.reload.tone).to eq('cordial e curto')
      expect(Array(thread.reload.messages).pluck('role')).not_to include('assistant')
    end
  end

  describe 'quando o agente ainda é rascunho' do
    before do
      agent.update!(status: :draft, enabled: false)
      rodar(saida)
    end

    it 'fecha como antes, para a criação seguir para a revisão' do
      expect(estado).to include('applied' => true, 'needs_more_info' => false)
    end
  end

  describe 'quando o Construtor muda só o tipo do agente' do
    before { rodar(saida('agent_type' => 'sdr')) }

    it 'conta como mudança' do
      expect(estado).to include('applied' => true)
      expect(agent.reload.agent_type).to eq('sdr')
    end
  end
end

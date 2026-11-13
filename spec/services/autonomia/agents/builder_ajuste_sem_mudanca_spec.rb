require 'rails_helper'

# #2984 — o "Mudar conversando" nas contas fora da Fase 2 dos agentes: o ajuste que não muda nada no agente, ou cuja
# escrita não venceu, não fecha como aplicado. Antes o turno terminava com `applied: true` e a tela mostrava "Pronto"
# para um pedido que não entrou. O aviso fixo que vai ao dono nunca vira pergunta pendente do Construtor.
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
  let(:estado) { thread.reload.state }
  let(:falas_do_construtor) { Array(thread.reload.messages).select { |m| m['role'] == 'assistant' }.pluck('content') }

  def texto(chave)
    I18n.t("autonomia.agents.ajuste.#{chave}", locale: Autonomia::Agents::Builder::TextosDoAjuste.idioma(nil, account))
  end

  # A saída do Construtor no ajuste: o agente como está, com o que o teste mudar por cima.
  def saida(overrides = {})
    { 'name' => 'Hubber', 'agent_type' => 'support', 'instruction' => 'Atenda o cliente da corretora com cordialidade.',
      'scaffold' => 'andaime', 'human_card' => 'O Hubber atende os clientes.', 'greeting' => 'Oi! Aqui é o Hubber.',
      'fallback_message' => 'Vou confirmar com a equipe.', 'handoff_rule' => 'Passe para a equipe quando o cliente pedir.',
      'starter_questions' => ['Como funciona?'], 'tone' => 'cordial', 'guardrails' => ['Não invente valores.'],
      'voice' => 'masculina', 'needs_more_info' => false, 'next_question' => '', 'user_asked_to_close' => false }.merge(overrides)
  end

  # Um turno do dono, com o Construtor dublado. Cada turno tem o seu Construtor, como no job.
  def rodar(parsed, fala: 'Tire a pergunta sobre o valor da garantia.', conversa: thread)
    construtor = described_class.new(account: account, build_thread: conversa.reload)
    allow(construtor).to receive(:client).and_return(instance_double(Crm::Ai::ResponsesClient, create: { text: parsed.to_json }))
    conversa.append_message!('user', fala)
    construtor.run!(conversa.begin_build!)
  end

  it 'está fora da Fase 2 dos agentes' do
    expect(Autonomia::Agents::Fase2.ligada?(account)).to be(false)
  end

  describe 'quando o Construtor devolve o agente igual ao que já era' do
    before { rodar(saida) }

    it 'não fecha como aplicado e deixa a conversa aberta' do
      expect(thread.reload).to be_ready
      expect(estado).to include('applied' => false, 'needs_more_info' => true, 'next_question' => texto(:sem_pedido))
    end

    it 'responde ao dono com o texto fixo, nunca com um texto do modelo' do
      expect(falas_do_construtor).to eq([texto(:sem_pedido)])
    end

    it 'não deixa o aviso fixo como pergunta pendente do turno seguinte' do
      seguinte = described_class.new(account: account, build_thread: thread.reload)

      expect(seguinte.send(:pending_question)).to eq('')
      expect(seguinte.send(:pending_request_context)).to eq('')
    end

    it 'não leva o aviso fixo como pendência para a sessão nova' do
      proxima = Autonomia::Agents::BuildThread.create!(account: account, agent: agent)

      proxima.inherit_pending_question!

      expect(proxima.reload.state['pending_question']).to be_nil
    end

    it 'não grava o aviso fixo no cartão quando o dono manda fechar no turno seguinte' do
      rodar(saida('user_asked_to_close' => true), fala: 'Deixa assim, pode fechar.')

      expect(agent.reload.human_card).to eq('O Hubber atende os clientes.')
      expect(estado).to include('applied' => false)
    end

    it 'aplica o pedido de verdade que vier depois, e a pergunta do Construtor volta a valer como pendência' do
      rodar(saida('greeting' => 'Olá!', 'needs_more_info' => true, 'next_question' => 'Mais formal ou informal?'),
            fala: 'Troque a saudação.')
      expect(described_class.new(account: account, build_thread: thread.reload).send(:pending_question))
        .to eq('Mais formal ou informal?')

      rodar(saida('greeting' => 'Olá!'), fala: 'Informal.')

      expect(agent.reload.greeting).to eq('Olá!')
      expect(estado).to include('applied' => true, 'needs_more_info' => false)
    end
  end

  describe 'quando o Construtor muda algo no agente' do
    before { rodar(saida('tone' => 'cordial e curto')) }

    it 'fecha como aplicado, sem pergunta' do
      expect(estado).to include('applied' => true, 'needs_more_info' => false)
      expect(agent.reload.tone).to eq('cordial e curto')
      expect(falas_do_construtor).to be_empty
    end
  end

  describe 'quando o Construtor muda só o tipo do agente' do
    before { rodar(saida('agent_type' => 'sdr')) }

    it 'conta como mudança' do
      expect(estado).to include('applied' => true)
      expect(agent.reload.agent_type).to eq('sdr')
    end
  end

  describe 'quando o Construtor muda só uma chave da configuração' do
    before { rodar(saida('voice' => 'feminina')) }

    it 'conta como mudança' do
      expect(estado).to include('applied' => true, 'needs_more_info' => false)
      expect(agent.reload.config['voice']).to eq('feminina')
    end
  end

  describe 'quando o agente guarda na configuração chaves que o Construtor não escreve' do
    before do
      agent.update!(config: agent.config.merge('topic_map' => { 'precos' => 3 }))
      rodar(saida)
    end

    it 'a saída igual continua sem mudança, e as chaves ficam' do
      expect(estado).to include('applied' => false, 'next_question' => texto(:sem_pedido))
      expect(agent.reload.config['topic_map']).to eq('precos' => 3)
    end
  end

  describe 'quando o agente está pausado' do
    before do
      agent.update!(status: :paused)
      rodar(saida)
    end

    it 'vale a mesma regra do agente que atende' do
      expect(estado).to include('applied' => false, 'needs_more_info' => true, 'next_question' => texto(:sem_pedido))
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

  describe 'quando existe um ajuste mais novo do mesmo agente' do
    before do
      thread
      Autonomia::Agents::BuildThread.create!(account: account, agent: agent)
      rodar(saida('tone' => 'cordial e curto'))
    end

    it 'não grava e não fecha como aplicado: avisa que o ajuste mais novo vale' do
      expect(agent.reload.tone).to eq('cordial')
      expect(estado).to include('applied' => false, 'needs_more_info' => true, 'next_question' => texto(:superado))
      expect(falas_do_construtor).to eq([texto(:superado)])
    end
  end
end

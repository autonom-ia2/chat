require 'rails_helper'

RSpec.describe Autonomia::Agents::Builder do
  let(:account) { create(:account) }
  let(:thread) { Autonomia::Agents::BuildThread.create!(account: account) }
  let(:builder) { described_class.new(account: account, build_thread: thread) }

  def stub_model_output(parsed)
    fake_client = instance_double(Crm::Ai::ResponsesClient, create: { text: parsed.to_json })
    allow(builder).to receive(:client).and_return(fake_client)
  end

  describe 'assistant turn persistence (E1)' do
    let(:question) { 'Qual o nome do agente?' }

    before do
      thread.append_message!('user', 'Quero um agente de suporte')
      stub_model_output('needs_more_info' => true, 'next_question' => question)
    end

    it 'persists the interview question as an assistant message on the thread' do
      # Arrange
      token = thread.begin_build!

      # Act
      builder.run!(token)

      # Assert
      last = Array(thread.reload.messages).last
      expect(last['role']).to eq('assistant')
      expect(last['content']).to eq(question)
      expect(thread.state['next_question']).to eq(question)
      expect(thread).to be_ready
    end

    it 'does not duplicate the assistant turn when the same question repeats back to back' do
      # Arrange
      builder.run!(thread.begin_build!)

      # Act
      builder.run!(thread.begin_build!)

      # Assert
      assistant_turns = Array(thread.reload.messages).select { |m| m['role'] == 'assistant' }
      expect(assistant_turns.size).to eq(1)
    end

    it 'skips persistence when the generation was superseded (token lost)' do
      # Arrange — o job da 1ª geração morreu (processing além da janela stale) e uma nova
      # geração reassumiu o slot via claim atômico; o token antigo perdeu.
      stale_token = thread.begin_build!
      travel_to(10.minutes.from_now) { thread.begin_build! }

      # Act
      builder.run!(stale_token)

      # Assert
      expect(Array(thread.reload.messages).pluck('role')).not_to include('assistant')
    end
  end

  describe 'knowledge opt-out context (E5)' do
    let(:agent) do
      Autonomia::Agents::Agent.create!(
        account: account, name: 'Rascunho', agent_type: 'support', mode: :guided,
        status: :draft, enabled: false
      )
    end

    context 'when the thread was opened with with_knowledge=false' do
      before do
        thread.persist_start_options!(type: 'support', with_knowledge: false)
        thread.save!
        thread.update!(agent: agent)
      end

      it 'suppresses the ask-once material confirmation block and reports the choice as confirmed' do
        # Act
        context = builder.send(:materials_status_context)

        # Assert
        expect(context).not_to include('pergunte UMA vez')
        expect(context).to include('usuário declarou/confirmou não ter material: true')
      end

      it 'tells the model not to ask for the no-knowledge confirmation' do
        # Act
        context = builder.send(:knowledge_intent_context)

        # Assert
        expect(context).to include('NÃO pergunte se pode criar sem base de conhecimento')
        expect(context).to include('NÃO peça documentos')
      end
    end

    context 'when the thread keeps the default with-knowledge flow' do
      before do
        thread.persist_start_options!(type: 'support')
        thread.save!
        thread.update!(agent: agent)
      end

      it 'keeps the ask-once material confirmation block' do
        # Act
        context = builder.send(:materials_status_context)

        # Assert
        expect(context).to include('pergunte UMA vez')
        expect(context).to include('usuário declarou/confirmou não ter material: false')
      end

      it 'emits no knowledge opt-out block' do
        expect(builder.send(:knowledge_intent_context)).to eq('')
      end
    end
  end

  # A guarda de knowledge_intent_context estava INVERTIDA para o caso de ajuste: em modo AJUSTE o bloco
  # que PROÍBE perguntar sobre base de conhecimento era justamente o suprimido, então todo ajuste voltava
  # a perguntar "posso criar sem base?" num agente que já existe e está rodando.
  describe 'knowledge question suppression in adjust mode' do
    let(:agent) do
      Autonomia::Agents::Agent.create!(
        account: account, name: 'Agente vivo', agent_type: 'support', mode: :guided,
        status: :active, enabled: true, instruction: 'Instrução fechada do agente.'
      )
    end

    before { thread.update!(agent: agent) }

    it 'tells the model to NEVER ask about the knowledge base, because the agent already exists' do
      # Act
      context = builder.send(:knowledge_intent_context)

      # Assert
      expect(context).to include('NUNCA pergunte se pode criar/ajustar o agente sem base de conhecimento')
      expect(context).to include('NÃO peça documentos')
    end

    it 'drops the ask-once material confirmation from the materials status block' do
      # Act — agente sem nenhuma fonte de conhecimento: era exatamente o caso que reabria a pergunta
      context = builder.send(:materials_status_context)

      # Assert
      expect(context).not_to include('pergunte UMA vez')
    end

    it 'does not let a close-intent phrase discard a clarifying question raised during the adjust' do
      # Arrange — pedido NOVO que casa CLOSE_INTENT_PATTERNS ("pode criar") sem responder a pergunta
      # pendente: antes isso virava ordem de fechar e a pergunta era descartada.
      thread.append_message!('user', 'pode criar uma saudação nova também')

      # Act / Assert
      expect(builder.send(:close_intent?)).to be(true)
      expect(builder.send(:force_close?)).to be(false)
    end
  end

  # O portão §5.4 foi PULADO num agente real: o dono mandou "pode finalizar" com a pergunta "quais dados
  # a agente deve coletar" ainda aberta, o buraco foi preenchido com a coleta genérica do tipo e ele
  # operou dias sem saber. Fechar continua liberado; fechar EM SILÊNCIO, não.
  describe 'gap disclosure on close' do
    def close_payload(overrides = {})
      {
        'name' => 'Ana', 'agent_type' => 'sdr', 'instruction' => 'Instrução completa da Ana.',
        'scaffold' => 'andaime', 'human_card' => 'A Ana faz a pré-venda e encaminha o lead.',
        'greeting' => 'Oi!', 'fallback_message' => 'Vou verificar.', 'handoff_rule' => 'Passa para humano.',
        'starter_questions' => [], 'tone' => 'cordial', 'guardrails' => [], 'voice' => 'feminina',
        'needs_more_info' => false, 'next_question' => ''
      }.merge(overrides)
    end

    it 'records the unanswered question in the human_card without blocking the close' do
      # Arrange — pergunta viva na virada do turno e o dono responde com uma ordem de fechar.
      question = 'Quais dados mínimos a Ana deve coletar antes de encaminhar o lead?'
      thread.append_message!('assistant', question)
      thread.update!(state: thread.state.to_h.merge('needs_more_info' => true, 'next_question' => question))
      thread.append_message!('user', 'Terminei, você pode finalizar o agente.')
      stub_model_output(close_payload)

      # Act
      builder.run!(thread.begin_build!)

      # Assert
      agent = thread.reload.agent
      expect(agent.human_card).to include(question)
      expect(agent.human_card).to include('padrão genérico')
      expect(agent.instruction).to eq('Instrução completa da Ana.')
    end

    it 'records the missing knowledge base when the ask-once confirmation never happened' do
      # Arrange — sem material, sem opt-out na abertura e sem a confirmação do §5.4.
      thread.append_message!('user', 'pode fechar')
      stub_model_output(close_payload)

      # Act
      builder.run!(thread.begin_build!)

      # Assert
      expect(thread.reload.agent.human_card).to include('sem base de conhecimento')
    end

    it 'keeps the human_card clean when nothing was left open' do
      # Arrange — base dispensada na abertura (decisão do dono) e nenhuma pergunta pendente.
      thread.persist_start_options!(type: 'sdr', with_knowledge: false)
      thread.save!
      thread.append_message!('user', 'A Ana coleta nome, cidade e tipo de seguro.')
      stub_model_output(close_payload)

      # Act
      builder.run!(thread.begin_build!)

      # Assert
      expect(thread.reload.agent.human_card).to eq('A Ana faz a pré-venda e encaminha o lead.')
    end
  end

  # O ApplicationRecord valida o tamanho de TODA coluna string (255) e text (20.000). Sem teto, o
  # `tone` gerado estourava e o save! derrubava o apply inteiro (RecordInvalid) — o dono perdia o
  # ajuste em silêncio. Truncar é sempre melhor que perder o pedido.
  describe '.map_attributes character budget' do
    let(:tone_limit) { described_class.write_limit_for(:tone) }

    def parsed_with(overrides)
      {
        'name' => 'Agente', 'agent_type' => 'support', 'instruction' => 'i', 'scaffold' => 's',
        'human_card' => 'h', 'greeting' => 'g', 'fallback_message' => 'f', 'handoff_rule' => 'r',
        'starter_questions' => [], 'tone' => 'cordial', 'guardrails' => [], 'voice' => 'feminina'
      }.merge(overrides)
    end

    it 'truncates an oversized tone to the write limit instead of raising on save' do
      # Arrange
      long_tone = (['palavra'] * 400).join(' ')

      # Act
      attrs = described_class.map_attributes(parsed_with('tone' => long_tone))

      # Assert
      expect(long_tone.length).to be > tone_limit
      expect(attrs[:tone].length).to be <= tone_limit
      expect(Autonomia::Agents::Agent.new(account: account, name: 'x', agent_type: 'support', tone: attrs[:tone]))
        .to be_valid
    end

    it 'cuts on a word boundary and adds no ellipsis' do
      # Act
      attrs = described_class.map_attributes(parsed_with('tone' => (['palavra'] * 400).join(' ')))

      # Assert
      expect(attrs[:tone]).not_to end_with('...')
      expect(attrs[:tone]).to end_with('palavra')
    end

    it 'reports which fields were truncated, without echoing their content' do
      # Arrange
      truncated = []

      # Act
      described_class.map_attributes(
        parsed_with('tone' => 'a' * (tone_limit + 1),
                    'greeting' => 'b' * (described_class.write_limit_for(:greeting) + 1)),
        truncated: truncated
      )

      # Assert
      expect(truncated).to contain_exactly('greeting', 'tone')
    end

    it 'leaves fields within the budget untouched' do
      # Arrange
      truncated = []

      # Act
      attrs = described_class.map_attributes(parsed_with('tone' => 'cordial e direto'), truncated: truncated)

      # Assert
      expect(attrs[:tone]).to eq('cordial e direto')
      expect(truncated).to be_empty
    end
  end
end

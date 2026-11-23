require 'rails_helper'

RSpec.describe Autonomia::Agents::Answerer do
  let(:account) { create(:account) }

  let(:model_reply) do
    {
      reply: 'Posso ajudar sim!', confidence: 0.9, should_handoff: false, handoff_reason: nil,
      used_snippet_ids: [], answered_from_knowledge: false
    }.to_json
  end

  before do
    resolver = instance_double(Crm::Ai::CredentialResolver, resolve: 'ai-credential')
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
    client = instance_double(Crm::Ai::ResponsesClient, create_with_tool_executor: { text: model_reply })
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
  end

  def create_agent(config)
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
      instruction: 'Atenda o cliente.', config: config
    )
  end

  describe 'mensagem de quando não souber (#2381)' do
    it 'pede o bloco do dono só quando a fala sai como está (trust_instruction)' do
      agent = create_agent('with_knowledge' => false)
      expect(Autonomia::Agents::PromptBuilder).to receive(:new).with(hash_including(mensagem_do_dono: true)).and_call_original

      described_class.new(agent: agent, query: 'oi', trust_instruction: true).answer
    end

    it 'não pede o bloco no caminho com portão (copiloto e Guia)' do
      agent = create_agent('with_knowledge' => false)
      expect(Autonomia::Agents::PromptBuilder).to receive(:new).with(hash_including(mensagem_do_dono: false)).and_call_original

      described_class.new(agent: agent, query: 'oi').answer
    end
  end

  describe 'knowledge retrieval skip (C3)' do
    it 'never instantiates the Retriever for an agent with with_knowledge=false and still answers' do
      # Arrange
      agent = create_agent('with_knowledge' => false)
      expect(Autonomia::Agents::Retriever).not_to receive(:new)

      # Act
      result = described_class.new(agent: agent, query: 'oi', trust_instruction: true).answer

      # Assert
      expect(result.reply).to eq('Posso ajudar sim!')
    end

    it "treats the string 'false' (jsonb form) as knowledge disabled too" do
      # Arrange
      agent = create_agent('with_knowledge' => 'false')
      expect(Autonomia::Agents::Retriever).not_to receive(:new)

      # Act
      result = described_class.new(agent: agent, query: 'oi', trust_instruction: true).answer

      # Assert
      expect(result.reply).to eq('Posso ajudar sim!')
    end

    it 'runs retrieval when the with_knowledge key is absent (historic default = with knowledge)' do
      # Arrange
      agent = create_agent({})
      retriever = instance_double(Autonomia::Agents::Retriever, retrieve: [])
      expect(Autonomia::Agents::Retriever).to receive(:new).with(agent: agent).and_return(retriever)

      # Act
      result = described_class.new(agent: agent, query: 'oi', trust_instruction: true).answer

      # Assert
      expect(result.reply).to eq('Posso ajudar sim!')
    end

    it 'runs retrieval when with_knowledge is explicitly true' do
      # Arrange
      agent = create_agent('with_knowledge' => true)
      retriever = instance_double(Autonomia::Agents::Retriever, retrieve: [])
      expect(Autonomia::Agents::Retriever).to receive(:new).with(agent: agent).and_return(retriever)

      # Act
      described_class.new(agent: agent, query: 'oi', trust_instruction: true).answer
    end
  end

  # #284 — o modo instrução-dirigido só REPASSA o sinal should_handoff do modelo (a resposta não muda).
  describe 'trust_instruction handoff signal' do
    let(:model_reply) do
      { reply: 'Vou te passar para um atendente.', confidence: 0.7, should_handoff: true,
        handoff_reason: 'human_requested', used_snippet_ids: [], answered_from_knowledge: false }.to_json
    end

    it 'passes the instruction handoff signal through untouched' do
      agent = create_agent('with_knowledge' => false)

      result = described_class.new(agent: agent, query: 'quero falar com humano', trust_instruction: true).answer

      expect(result.reply).to eq('Vou te passar para um atendente.')
      expect(result.handoff).to eq({ should: true, reason: 'human_requested' })
    end
  end

  describe 'model handoff signal with grounded answer' do
    let(:agent) do
      agent = create_agent('with_knowledge' => true)
      allow(agent).to receive(:accepted_sources).and_return(instance_double(ActiveRecord::Relation, exists?: true))
      agent
    end
    let(:source) { instance_double(Autonomia::Agents::Source, reference: 'manual.pdf', external_link: nil) }
    let(:snippet) do
      knowledge_snippet(123, 'O kit pode ser impresso em papel A4.', 0.2)
    end
    let(:weak_snippet) do
      knowledge_snippet(124, 'Texto sem relação forte.', 0.8)
    end

    def knowledge_snippet(id, content, distance)
      Struct.new(:id, :content, :source, :neighbor_distance).new(id, content, source, distance)
    end

    def stub_retrieval(snippets)
      allow(Autonomia::Agents::Retriever).to receive(:new)
        .and_return(instance_double(Autonomia::Agents::Retriever, retrieve: snippets))
    end

    def stub_model(reply_hash)
      client = instance_double(Crm::Ai::ResponsesClient, create_with_tool_executor: { text: reply_hash.to_json })
      allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    end

    it 'ignores a generic model handoff when the answer is grounded and confident' do
      stub_retrieval([snippet])
      stub_model(reply: 'O kit pode ser impresso em papel A4.', confidence: 0.97,
                 should_handoff: true, handoff_reason: 'Outro / não especificado',
                 used_snippet_ids: [snippet.id], answered_from_knowledge: true)

      result = described_class.new(agent: agent, query: 'Posso imprimir o kit em A4?').answer

      expect(result.reply).to eq('O kit pode ser impresso em papel A4.')
      expect(result.handoff).to eq({ should: false, reason: nil })
      expect(result.answered_from_knowledge).to be(true)
    end

    # #2850 — sem o vetor da pergunta, o Answerer pede os trechos só pela palavra (sem distância). A distância vazia não
    # rebaixa a resposta que o modelo diz vir da base: `grounded_by_instruction` mantém a confiança declarada, e o
    # atendimento ao cliente não tem portão de confiança. Quem decide se o trecho serve é o modelo.
    it 'asks the words when the vector fails, and keeps the answer of the model over a piece without distance', :aggregate_failures do
      sem_distancia = knowledge_snippet(125, 'O kit pode ser impresso em papel A4.', nil)
      retriever = instance_double(Autonomia::Agents::Retriever, retrieve: [sem_distancia])
      allow(Autonomia::Agents::Retriever).to receive(:new).and_return(retriever)
      stub_model(reply: 'O kit pode ser impresso em papel A4.', confidence: 0.97, should_handoff: false, handoff_reason: nil,
                 used_snippet_ids: [sem_distancia.id], answered_from_knowledge: true)

      result = described_class.new(agent: agent, query: 'Posso imprimir o kit em A4?').answer

      expect(retriever).to have_received(:retrieve).with('Posso imprimir o kit em A4?', top_k: anything, por_palavra_sem_vetor: true)
      expect(result.reply).to eq('O kit pode ser impresso em papel A4.')
      expect(result.handoff[:should]).to be(false)
    end

    it 'keeps the handoff when the grounded answer is below the confidence threshold' do
      stub_retrieval([snippet])
      stub_model(reply: 'Talvez o kit possa ser impresso em A4.', confidence: 0.4,
                 should_handoff: true, handoff_reason: 'Outro / não especificado',
                 used_snippet_ids: [snippet.id], answered_from_knowledge: true)

      result = described_class.new(agent: agent, query: 'Posso imprimir o kit em A4?').answer

      expect(result.reply).to be_nil
      expect(result.handoff[:should]).to be(true)
    end

    it 'keeps the handoff when the model did not ground the answer in retrieved knowledge' do
      stub_retrieval([snippet])
      stub_model(reply: 'Vamos verificar com a equipe.', confidence: 0.97,
                 should_handoff: true, handoff_reason: 'Outro / não especificado',
                 used_snippet_ids: [], answered_from_knowledge: false)

      result = described_class.new(agent: agent, query: 'Como solicito um kit?').answer

      expect(result.reply).to be_nil
      expect(result.handoff[:should]).to be(true)
    end

    it 'keeps the handoff when claimed knowledge has no used snippet and no strong retrieval anchor' do
      stub_retrieval([weak_snippet])
      stub_model(reply: 'Vamos verificar com a equipe.', confidence: 0.97,
                 should_handoff: true, handoff_reason: 'Outro / não especificado',
                 used_snippet_ids: [], answered_from_knowledge: true)

      result = described_class.new(agent: agent, query: 'Como solicito um kit?').answer

      expect(result.reply).to be_nil
      expect(result.handoff[:should]).to be(true)
    end

    it 'keeps explicit human/action handoff reasons even when a snippet was used' do
      %w[human_requested action_required].each do |reason|
        stub_retrieval([snippet])
        stub_model(reply: 'Vou te passar para um atendente.', confidence: 0.97,
                   should_handoff: true, handoff_reason: reason,
                   used_snippet_ids: [snippet.id], answered_from_knowledge: true)

        result = described_class.new(agent: agent, query: 'Quero falar com um atendente').answer

        expect(result.reply).to be_nil
        expect(result.handoff).to eq({ should: true, reason: reason })
      end
    end
  end

  describe 'retrieval_query override' do
    it 'retrieves the service and deadline question for a numeric choice while keeping the original prompt', :aggregate_failures do
      agent = create_agent('with_knowledge' => true)
      history = [{ role: 'user', content: 'Quero fazer analise de amostras' },
                 { role: 'assistant', content: 'Qual o material e quantas amostras?' },
                 { role: 'user', content: 'sangue.3' },
                 { role: 'assistant', content: 'Temos prazos de 1, 3 e 7 dias. Qual prazo voce prefere?' }]
      retriever = instance_double(Autonomia::Agents::Retriever, retrieve: [])
      allow(Autonomia::Agents::Retriever).to receive(:new).and_return(retriever)
      expect(Autonomia::Agents::PromptBuilder).to receive(:new)
        .with(hash_including(query: '3', history: history)).and_call_original

      Autonomia::Agents::Playground.new(agent: agent, message: '3', history: history).run

      expect(retriever).to have_received(:retrieve)
        .with("3\nsangue.3\nQuero fazer analise de amostras\nQual prazo voce prefere?",
              top_k: Autonomia::Agents::Config::ANSWER_TOP_K, por_palavra_sem_vetor: true)
    end

    it 'retrieves procedure context for a negative reply without changing the model question', :aggregate_failures do
      agent = create_agent('with_knowledge' => true)
      history = [{ role: 'user', content: 'Como configuro o plano Equipe?' },
                 { role: 'assistant', content: 'O preco anterior era R$ 80. Voce sabe importar seus usuarios?' }]
      retriever = instance_double(Autonomia::Agents::Retriever, retrieve: [])
      allow(Autonomia::Agents::Retriever).to receive(:new).and_return(retriever)
      expect(Autonomia::Agents::PromptBuilder).to receive(:new)
        .with(hash_including(query: 'não', history: history)).and_call_original

      described_class.new(agent: agent, query: 'não', history: history, trust_instruction: true).answer

      expect(retriever).to have_received(:retrieve)
        .with("não\nComo configuro o plano Equipe?\nVoce sabe importar seus usuarios?",
              top_k: Autonomia::Agents::Config::ANSWER_TOP_K, por_palavra_sem_vetor: true)
    end

    it 'retains the subject across split replies in both the simulator and the shared answering engine', :aggregate_failures do
      agent = create_agent('with_knowledge' => true)
      question = 'Qual o valor do plano Equipe para 15 usuarios?'
      query = 'Na verdade, serão só 2 usuários.'
      history = [{ role: 'user', content: question }, { role: 'assistant', content: 'O valor anterior era R$ 80.' },
                 { role: 'assistant', content: 'Voce sabe importar seus usuarios?' },
                 { role: 'user', content: 'Na verdade, serão só 10 usuários.' },
                 { role: 'assistant', content: 'O total anterior era R$ 800.' },
                 { role: 'assistant', content: 'O plano tem diferentes prazos.' },
                 { role: 'assistant', content: 'Qual prazo voce prefere?' },
                 { role: 'user', content: '3' },
                 { role: 'assistant', content: 'Prazo selecionado.' },
                 { role: 'assistant', content: 'Voce sabe importar seus usuarios?' }]
      retriever = instance_double(Autonomia::Agents::Retriever, retrieve: [])
      allow(Autonomia::Agents::Retriever).to receive(:new).and_return(retriever)
      expect(Autonomia::Agents::PromptBuilder).to receive(:new).with(hash_including(query: query, history: history)).twice.and_call_original

      described_class.new(agent: agent, query: query, history: history, trust_instruction: true).answer
      Autonomia::Agents::Playground.new(agent: agent, message: query, history: history).run

      expect(retriever).to have_received(:retrieve).with(
        "#{query}\n#{question}", top_k: Autonomia::Agents::Config::ANSWER_TOP_K, por_palavra_sem_vetor: true
      ).twice
    end

    it 'keeps an explicit retrieval query instead of replacing it with conversational context' do
      agent = create_agent('with_knowledge' => true)
      retriever = instance_double(Autonomia::Agents::Retriever, retrieve: [])
      allow(Autonomia::Agents::Retriever).to receive(:new).and_return(retriever)
      history = [{ role: 'user', content: 'Quanto custa o plano Equipe?' }]

      described_class.new(agent: agent, query: 'Vou fazer só de 10.', history: history,
                          retrieval_query: 'consulta explicita', trust_instruction: true).answer

      expect(retriever).to have_received(:retrieve)
        .with('consulta explicita', top_k: Autonomia::Agents::Config::ANSWER_TOP_K, por_palavra_sem_vetor: true)
    end

    it 'retrieves with the bare question when the composed query embeds context first' do
      # Arrange — copiloto chat: query composta = transcrição antes do pedido real
      agent = create_agent('with_knowledge' => true)
      composed = "CONTEXTO: #{'bla ' * 100}\nPEDIDO DO ATENDENTE:\nqual o prazo de entrega?"
      retriever = instance_double(Autonomia::Agents::Retriever)
      allow(Autonomia::Agents::Retriever).to receive(:new).and_return(retriever)
      expect(retriever).to receive(:retrieve)
        .with('qual o prazo de entrega?', top_k: Autonomia::Agents::Config::ANSWER_TOP_K, por_palavra_sem_vetor: true)
        .and_return([])

      # Act
      described_class.new(agent: agent, query: composed, trust_instruction: true,
                          retrieval_query: 'qual o prazo de entrega?').answer
    end

    it 'falls back to the full query when no retrieval_query is given' do
      # Arrange
      agent = create_agent('with_knowledge' => true)
      retriever = instance_double(Autonomia::Agents::Retriever)
      allow(Autonomia::Agents::Retriever).to receive(:new).and_return(retriever)
      expect(retriever).to receive(:retrieve)
        .with('oi', top_k: Autonomia::Agents::Config::ANSWER_TOP_K, por_palavra_sem_vetor: true).and_return([])

      # Act
      described_class.new(agent: agent, query: 'oi', trust_instruction: true).answer
    end
  end

  describe 'retrieval diagnostics' do
    it 'records retrieved IDs separately from valid used IDs without message content', :aggregate_failures do
      agent = create_agent('with_knowledge' => true)
      answerer = described_class.new(agent: agent, query: 'private customer query')
      snippets = [Struct.new(:id).new(101), Struct.new(:id).new(102)]
      parsed = { 'used_snippet_ids' => [102, 'private token', 999], 'should_handoff' => true,
                 'answered_from_knowledge' => false, 'reply' => 'private reply', 'handoff_reason' => 'private reason' }
      allow(Rails.logger).to receive(:info)

      answerer.send(:log_retrieval, snippets, parsed)

      expect(Rails.logger).to have_received(:info).with(satisfy do |line|
        JSON.parse(line) == {
          'event' => 'autonomia.agents.retrieval', 'agent_id' => agent.id, 'feature' => 'agente_resposta',
          'retrieval_query_overridden' => false, 'retrieved_snippet_ids' => [101, 102], 'used_snippet_ids' => [102],
          'model_handoff' => true, 'answered_from_knowledge' => false, 'generation_failed' => false
        }
      end)
    end

    it 'records failed generation with no used snippets' do
      agent = create_agent('with_knowledge' => true)
      answerer = described_class.new(agent: agent, query: 'oi')
      allow(Rails.logger).to receive(:info)

      answerer.send(:log_retrieval, [], nil)

      expect(Rails.logger).to have_received(:info).with(satisfy do |line|
        JSON.parse(line).slice('used_snippet_ids', 'generation_failed') == { 'used_snippet_ids' => [], 'generation_failed' => true }
      end)
    end
  end

  # Cinto do desbloqueio de conhecimento geral (Codex HIGH #118): auto-rotulo "geral" nao libera
  # fato do NEGOCIO sem base; fato geral do MUNDO continua passando.
  describe 'ungrounded business claim belt' do
    let(:agent_with_kb) do
      agent = create_agent({})
      allow(agent).to receive(:accepted_sources).and_return(instance_double(ActiveRecord::Relation, exists?: true))
      allow(Autonomia::Agents::Retriever).to receive(:new)
        .and_return(instance_double(Autonomia::Agents::Retriever, retrieve: []))
      agent
    end

    def stub_model(reply_hash)
      client = instance_double(Crm::Ai::ResponsesClient, create_with_tool_executor: { text: reply_hash.to_json })
      allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    end

    it 'blocks a business fact mislabeled as general knowledge (no snippet, high confidence)' do
      # Arrange - modelo alucina fato do negocio e se auto-rotula "geral"
      stub_model(reply: 'Nosso plano cobre COVID ate o limite contratado.', confidence: 0.95,
                 should_handoff: false, handoff_reason: nil, used_snippet_ids: [],
                 answered_from_knowledge: false)

      # Act
      result = described_class.new(agent: agent_with_kb, query: 'cobre covid?').answer

      # Assert - rebaixado (0.50 < threshold 0.55) => handoff, nunca chega como resposta
      expect(result.handoff[:should]).to be(true)
      expect(result.answered_from_knowledge).to be(false)
    end

    it 'blocks the natural third-person form, whatever the threshold' do
      # Arrange - "O plano cobre..." (sem 1a pessoa): o ramo direto do portao independe do
      # threshold (Codex HIGH 2a rodada).
      stub_model(reply: 'O plano cobre COVID e o prazo de reembolso e de 30 dias.', confidence: 0.95,
                 should_handoff: false, handoff_reason: nil, used_snippet_ids: [],
                 answered_from_knowledge: false)

      # Act
      result = described_class.new(agent: agent_with_kb, query: 'cobre covid?').answer

      # Assert
      expect(result.handoff[:should]).to be(true)
    end

    it 'blocks passive/existential business claim phrasings (Codex round 3)' do
      # Arrange/Act/Assert - cada forma comum de claim sem sujeito explicito deve cair no cinto
      [
        'COVID esta coberto ate o limite contratado.',
        'Ha cobertura para COVID ate o limite contratado.',
        'A cobertura para COVID esta incluida no plano.',
        'O reembolso acontece em ate 30 dias.',
        'Plano contratado cobre COVID ate o limite.'
      ].each do |claim|
        stub_model(reply: claim, confidence: 0.95, should_handoff: false, handoff_reason: nil,
                   used_snippet_ids: [], answered_from_knowledge: false)
        result = described_class.new(agent: agent_with_kb, query: 'cobre covid?').answer
        expect(result.handoff[:should]).to be(true), "esperava handoff para: #{claim}"
      end
    end

    it 'lets genuine world knowledge through (no first-person business claim)' do
      # Arrange - fato publico estavel, sem 1a pessoa do negocio
      stub_model(reply: 'O Tratado de Schengen exige seguro viagem com cobertura minima de 30 mil euros.',
                 confidence: 0.9, should_handoff: false, handoff_reason: nil, used_snippet_ids: [],
                 answered_from_knowledge: false)

      # Act
      result = described_class.new(agent: agent_with_kb, query: 'paises do schengen?').answer

      # Assert
      expect(result.handoff[:should]).to be(false)
      expect(result.reply).to include('Schengen')
    end
  end

  # #941 — a falha da IA virava handoff sem rastro: não havia como saber por que o Guia ficou mudo.
  describe 'falha da IA' do
    let(:prompt_secreto) { 'PERGUNTA-QUE-NAO-PODE-IR-PRO-LOG' }

    def capturar_log
      linhas = []
      allow(Rails.logger).to receive(:warn).and_wrap_original do |original, *args, &block|
        linhas << args.first.to_s
        original.call(*args, &block)
      end
      yield
      linhas.join("\n")
    end

    it 'registra a classe do erro, o agente e a feature, nunca a mensagem que ecoa o prompt', :aggregate_failures do
      # Arrange
      agent = create_agent('with_knowledge' => false)
      client = instance_double(Crm::Ai::ResponsesClient)
      allow(client).to receive(:create_with_tool_executor)
        .and_raise(Crm::Ai::ResponsesClient::Error, "Invalid input: #{prompt_secreto}")
      allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)

      # Act
      log = capturar_log { described_class.new(agent: agent, query: prompt_secreto, feature: 'guia').answer }

      # Assert
      expect(log).to include("[autonomia][answerer] ia indisponivel agent=#{agent.id} feature=guia Crm::Ai::ResponsesClient::Error")
      expect(log).not_to include(prompt_secreto)
    end

    it 'registra JSON inválido do modelo pela classe, sem o texto devolvido', :aggregate_failures do
      # Arrange
      agent = create_agent('with_knowledge' => false)
      client = instance_double(Crm::Ai::ResponsesClient, create_with_tool_executor: { text: "nao-json #{prompt_secreto}" })
      allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)

      # Act
      log = capturar_log { described_class.new(agent: agent, query: prompt_secreto).answer }

      # Assert
      expect(log).to include("agent=#{agent.id} feature=agente_resposta JSON::ParserError")
      expect(log).not_to include(prompt_secreto)
    end
  end

  # Entrega 2 — a mensagem que a pessoa manda enquanto o Guia trabalha entra na próxima ida ao modelo, depois das
  # saídas da rodada. Quem decide parar, mudar ou seguir é o modelo; aqui só se prova que ela chega, e só ao Guia.
  describe 'mensagem nova no meio do trabalho' do
    let(:agent) { create_agent('with_knowledge' => false) }

    def saidas_da_rodada(operador)
      described_class.new(agent: agent, query: 'cria três etiquetas', operador: operador).send(:execute_tool_calls, [])
    end

    it 'entra com o aviso e como fala da pessoa, na ordem', :aggregate_failures do
      operador = instance_double(Autonomia::Guide::Contexto, mensagens_novas: ['pensei melhor', 'pare'])

      saidas = saidas_da_rodada(operador)

      expect(saidas.pluck(:role)).to eq(%w[developer user user])
      expect(saidas.map { |m| m[:content].first[:text] })
        .to eq([described_class::AVISO_DE_MENSAGEM_NOVA, 'pensei melhor', 'pare'])
    end

    it 'sem mensagem nova, a rodada segue igual' do
      expect(saidas_da_rodada(instance_double(Autonomia::Guide::Contexto, mensagens_novas: []))).to eq([])
    end

    # O atendimento não tem `operador`: o núcleo dividido com os agentes de cliente não muda para eles.
    it 'no atendimento (sem operador) nada entra' do
      expect(saidas_da_rodada(nil)).to eq([])
    end
  end
end

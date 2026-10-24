require 'rails_helper'

# #2154, o caso real (conversa 6987): a instrução manda passar, o agente avisa em mais de um pedaço e a conversa precisa
# chegar a uma pessoa. Ponta a ponta, com a flag `agente_so_informa`: o turno do agente (humanização ligada), a cadeia
# de pedaços inteira, a avaliação real da IA de Atribuição (só o classificador dublado, devolvendo "transferir") e a
# entrega pelo Crm::Entrega a um membro online da caixa. Todos os pedaços saem ANTES de a pessoa entrar no nome.
RSpec.describe 'Agente só informa: conversa 6987' do # rubocop:disable RSpec/DescribeClass
  include_context 'with crm responsible agent'

  let(:pessoa) { create(:user, account: account) }
  let(:fala) do
    [
      'Entendi, você quer revisar as condições do contrato e entender o que muda na renovação deste ano, com as ' \
      'coberturas novas e o valor da parcela que chegou diferente do combinado na última conversa.',
      'Esse é um caso para a nossa equipe, que tem acesso ao seu contrato completo. Vou chamar alguém da equipe para ' \
      'te atender por aqui mesmo, e enquanto isso sigo à disposição para o que precisar.'
    ].join("\n\n")
  end
  let(:classificacao) do
    { suggested_stage_id: card.stage_id, confidence: 0.9, reasoning: 'r', value: nil,
      handoff: { intent: 'transferir', should_handoff: true, reason: 'o assistente avisou que chama a equipe', suggested_agent: nil },
      callback_request: nil, extracted_attributes: {}, score_signals: [] }
  end
  let(:card) do
    card = create_card(pipeline: comercial)
    card.stage.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r2_direct' } })
    card.reload
  end
  let!(:pergunta) do
    create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'quero falar com uma pessoa')
  end
  let(:pedacos_quando_entregou) { [] }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', AI_AGENT_MEDIA: 'false', AI_HUMANIZE_DELIVERY: 'true') { example.run }
  end

  before do
    account.enable_features!(Autonomia::Agents::AgenteSoInforma::FLAG)
    card
    inbox.add_members([pessoa.id])
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return({ pessoa.id => 'online' })
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow_any_instance_of(Crm::Ai::CredentialResolver).to receive_messages(configured?: true, resolve: nil) # rubocop:disable RSpec/AnyInstance
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(instance_double(Crm::Ai::ResponsesClient))
    allow(Crm::Ai::StageClassifier).to receive(:new).and_return(instance_double(Crm::Ai::StageClassifier, perform: classificacao))
    allow_any_instance_of(Autonomia::Agents::Operate::TypingIndicator).to receive(:on) # rubocop:disable RSpec/AnyInstance
    [Crm::Ai::AvaliacaoDepoisDaFala::CHAVE_DO_INTERVALO, Autonomia::Agents::Operate::CadeiaEmCurso::CHAVE].each do |chave|
      Redis::Alfred.delete(format(chave, conversa: conversation.id))
    end
    ia_avisa!
    # Quantos pedaços já tinham saído quando a Entrega rodou.
    allow(Crm::Entrega).to receive(:new).and_wrap_original do |original, **kwargs|
      pedacos_quando_entregou << respostas.count
      original.call(**kwargs)
    end
  end

  def ia_avisa!
    answer = Autonomia::Agents::AnswerResult.new(reply: fala, confidence: 0.9, handoff: { should: true, reason: 'human_requested' },
                                                 used_knowledge: [], answered_from_knowledge: false)
    allow(Autonomia::Agents::Answerer).to receive(:new).and_return(instance_double(Autonomia::Agents::Answerer, answer: answer))
  end

  def respostas = conversation.messages.outgoing.where(sender_type: 'AgentBot', private: false)

  def jobs(classe) = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job[:job] == classe }

  # Roda os jobs da classe, um de cada vez, como o Sidekiq faria (os que eles enfileiram também).
  def rodar!(classe)
    10.times do
      job = jobs(classe).first
      break if job.nil?

      ActiveJob::Base.queue_adapter.enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
  end

  it 'a fala sai inteira, e só depois a IA de Atribuição entrega a conversa ao membro online', :aggregate_failures do
    Autonomia::Agents::Operate::Responder.new(conversation: conversation, agent_inbox: vinculo_da_porta,
                                              reply_to_message_id: pergunta.id).perform
    expect(jobs(Crm::Ai::EvaluateCardJob)).to be_empty

    rodar!(Autonomia::Agents::Operate::ChunkedDeliveryJob)
    expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: porta)
    expect(jobs(Crm::Ai::EvaluateCardJob).size).to eq(1)

    rodar!(Crm::Ai::EvaluateCardJob)

    expect(respostas.count).to be > 1
    expect(respostas.reorder(:id).pluck(:content).join(' ').squish).to eq(fala.squish)
    expect(pedacos_quando_entregou).to eq([respostas.count])
    expect(conversation.reload).to have_attributes(assignee_id: pessoa.id, ai_assignee: nil)
    expect(Autonomia::Agents::AgentEvent.avisou_que_chama_alguem.where(conversation_id: conversation.id).count).to eq(1)
    expect(Autonomia::Agents::AgentEvent.handed_off.where(conversation_id: conversation.id).count).to eq(1)
  end

  it 'com o funil sem a IA, a conversa fica com o agente e o motivo aparece como evento dele', :aggregate_failures do
    comercial.update!(metadata: { 'ai' => { 'enabled' => false } })

    Autonomia::Agents::Operate::Responder.new(conversation: conversation, agent_inbox: vinculo_da_porta,
                                              reply_to_message_id: pergunta.id).perform
    rodar!(Autonomia::Agents::Operate::ChunkedDeliveryJob)

    expect(jobs(Crm::Ai::EvaluateCardJob)).to be_empty
    expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: porta)
    evento = Autonomia::Agents::AgentEvent.atribuicao_nao_avaliou.where(conversation_id: conversation.id).sole
    expect(evento.metadata).to eq('motivo' => 'pipeline_ai_disabled')
  end
end

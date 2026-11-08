require 'rails_helper'

# #2154 (regra do Rodrigo, 24/10): nenhum agente nosso passa a conversa. Com a flag `agente_so_informa`, o sinal
# `should_handoff` da instrução vira só o registro do turno: o agente responde o que a instrução manda ("vou chamar alguém
# da equipe") e continua atendendo. Depois que a fala sai (no último pedaço, na entrega em pedaços), a IA de Atribuição
# do CRM é chamada a avaliar (ContratoDoFunil.avaliar_depois_da_fala). O evento da cotação (ResponderAoEvento) segue
# passando a conversa, como antes.
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.')
  end
  let(:agent_inbox) { Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot) }
  let(:contrato) { Autonomia::Agents::ContratoDoFunil }
  let(:turno) { Autonomia::Agents::Operate::TurnoEmCurso }
  # A fala da conversa 6987: a instrução manda passar, e o agente avisa em mais de uma frase.
  # Dois parágrafos longos: a entrega em pedaços (ReplyChunker, soft_max de 260) manda em mais de uma mensagem.
  let(:fala) do
    [
      'Entendi, você quer revisar as condições do contrato e entender o que muda na renovação deste ano, com as ' \
      'coberturas novas e o valor da parcela que chegou diferente do combinado na última conversa.',
      'Esse é um caso para a nossa equipe, que tem acesso ao seu contrato completo. Vou chamar alguém da equipe para ' \
      'te atender por aqui mesmo, e enquanto isso sigo à disposição para o que precisar.'
    ].join("\n\n")
  end
  let!(:pergunta) do
    create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'quero falar com uma pessoa')
  end

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    conversation.update!(ai_assignee: agent_bot)
    account.enable_features!(Autonomia::Agents::AgenteSoInforma::FLAG)
    allow(contrato).to receive(:avaliar_depois_da_fala)
    allow(Autonomia::Agents::NotaDoEncaminhamento).to receive(:postar)
  end

  def ia_responde(texto = fala, should: true)
    answer = Autonomia::Agents::AnswerResult.new(reply: texto, confidence: 0.9, handoff: { should: should, reason: 'human_requested' },
                                                 used_knowledge: [], answered_from_knowledge: false)
    allow(Autonomia::Agents::Answerer).to receive(:new).and_return(instance_double(Autonomia::Agents::Answerer, answer: answer))
  end

  def responder = described_class.new(conversation: conversation, agent_inbox: agent_inbox, reply_to_message_id: pergunta.id)

  # O ReplyJob#trigger abriu o turno desta pergunta (#2154).
  def turno_aberto! = turno.abrir(conversation.id, pergunta.id)

  def respostas = conversation.messages.outgoing.where(sender_type: 'AgentBot', private: false)

  def pedacos_na_fila
    ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job[:job] == Autonomia::Agents::Operate::ChunkedDeliveryJob }
  end

  # Roda a cadeia de pedaços inteira, um job de cada vez, como o Sidekiq faria.
  def entregar_os_pedacos!
    10.times do
      job = pedacos_na_fila.first
      break if job.nil?

      ActiveJob::Base.queue_adapter.enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
  end

  def segue_com_o_agente!
    expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: agent_bot)
    expect(conversation.additional_attributes.to_h).not_to have_key(Conversation::BOT_HANDOFF_WAITING_SINCE_KEY)
    expect(Autonomia::Agents::AgentEvent.handed_off.count).to eq(0)
  end

  context 'with a humanização desligada (a entrega de uma mensagem só)' do
    around { |example| with_modified_env(AI_HUMANIZE_DELIVERY: 'false') { example.run } }

    it 'responde o que a instrução manda, continua atendendo e chama a Atribuição depois da fala', :aggregate_failures do
      ia_responde

      result = responder.perform

      expect(result.status).to eq(:replied)
      expect(result.message.content).to eq(fala)
      segue_com_o_agente!
      expect(contrato).to have_received(:avaliar_depois_da_fala).with(conversation).once
      evento = Autonomia::Agents::AgentEvent.avisou_que_chama_alguem.last
      expect(evento).to have_attributes(conversation_id: conversation.id, message_id: result.message.id, handoff_reason: 'human_requested')
    end

    it 'não posta a nota "antes de encaminhar" (a conversa não foi encaminhada) e guarda as recusas até a passagem' do
      Autonomia::Agents::Tools::RecusasRecentes.anotar(conversation.id, 'especialista_falhou')
      ia_responde

      responder.perform

      expect(Autonomia::Agents::NotaDoEncaminhamento).not_to have_received(:postar)
      chave = format(Autonomia::Agents::Tools::RecusasRecentes::CHAVE, conversa: conversation.id)
      expect(Redis::Alfred.ttl(chave)).to be > Autonomia::Agents::Tools::RecusasRecentes::VALIDADE.to_i
      Autonomia::Agents::Tools::RecusasRecentes.anotar(conversation.id, 'especialista_falhou')
      expect(Redis::Alfred.ttl(chave)).to be > Autonomia::Agents::Tools::RecusasRecentes::VALIDADE.to_i
    end

    it 'sem o sinal da instrução, não registra nem chama a Atribuição' do
      ia_responde('Claro, te ajudo.', should: false)

      responder.perform

      expect(contrato).not_to have_received(:avaliar_depois_da_fala)
      expect(Autonomia::Agents::AgentEvent.avisou_que_chama_alguem.count).to eq(0)
    end

    it 'a fala não saiu (uma pessoa assumiu durante a IA): não chama a Atribuição' do
      ia_responde
      allow_any_instance_of(described_class).to receive(:still_eligible?).and_return(true, false) # rubocop:disable RSpec/AnyInstance

      expect(responder.perform.status).to eq(:silenced)
      expect(contrato).not_to have_received(:avaliar_depois_da_fala)
    end

    it 'sem a flag, nada muda: o agente passa a conversa como hoje', :aggregate_failures do
      account.disable_features!(Autonomia::Agents::AgenteSoInforma::FLAG)
      ia_responde

      responder.perform

      expect(conversation.reload.additional_attributes.to_h).to have_key(Conversation::BOT_HANDOFF_WAITING_SINCE_KEY)
      expect(Autonomia::Agents::AgentEvent.handed_off.count).to eq(1)
      expect(Autonomia::Agents::NotaDoEncaminhamento).to have_received(:postar).with(conversation)
      expect(contrato).not_to have_received(:avaliar_depois_da_fala)
    end
  end

  context 'with a humanização ligada (a entrega em pedaços, o padrão)' do
    around { |example| with_modified_env(AI_HUMANIZE_DELIVERY: 'true') { example.run } }

    before { allow_any_instance_of(Autonomia::Agents::Operate::TypingIndicator).to receive(:on) } # rubocop:disable RSpec/AnyInstance

    it 'conversa 6987: a fala sai inteira, o agente segue e a Atribuição só é chamada depois do último pedaço', :aggregate_failures do
      turno_aberto!
      ia_responde
      responder_do_turno = responder
      expect(responder_do_turno.perform.status).to eq(:replied)
      expect(respostas.count).to eq(0)
      expect(contrato).not_to have_received(:avaliar_depois_da_fala)
      expect(pedacos_na_fila.size).to eq(1)
      # A fala ainda não saiu: nem o registro do aviso. A cadeia assumiu o turno, com o TTL dela.
      expect(Autonomia::Agents::AgentEvent.avisou_que_chama_alguem.count).to eq(0)
      expect(Redis::Alfred.ttl(turno.chave(conversation.id))).to be_between(1, turno::TTL_DA_CADEIA.to_i)
      expect(responder_do_turno.turno_segue?).to be(true)

      entregar_os_pedacos!

      expect(respostas.reorder(:id).pluck(:content).join(' ').squish).to eq(fala.squish)
      expect(respostas.count).to be > 1
      segue_com_o_agente!
      expect(contrato).to have_received(:avaliar_depois_da_fala).with(conversation).once
      evento = Autonomia::Agents::AgentEvent.avisou_que_chama_alguem.sole
      expect(evento).to have_attributes(message_id: respostas.reorder(:id).first.id, handoff_reason: 'human_requested')
      expect(turno.em_curso?(conversation.id)).to be(false)
    end

    it 'o cliente escreveu no meio da fala (turno mudou depois do 1º pedaço): a Atribuição avalia; a marca é do turno novo',
       :aggregate_failures do
      turno_aberto!
      ia_responde

      responder.perform
      job = pedacos_na_fila.first
      ActiveJob::Base.queue_adapter.enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
      nova = create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'e aí?')
      conversation.update!(additional_attributes: { Autonomia::Agents::Operate::ReplyJob::DEBOUNCE_KEY => { 'pending_message_id' => nova.id } })
      turno.abrir(conversation.id, nova.id)
      entregar_os_pedacos!

      expect(respostas.count).to eq(1)
      expect(contrato).to have_received(:avaliar_depois_da_fala).with(conversation).once
      expect(Redis::Alfred.get(turno.chave(conversation.id))).to eq(nova.id.to_s)
    end

    it 'sem a flag, a cadeia não leva a marca do aviso nem mexe na marca do turno', :aggregate_failures do
      account.disable_features!(Autonomia::Agents::AgenteSoInforma::FLAG)
      ia_responde

      responder.perform

      meta = ActiveJob::Arguments.deserialize(pedacos_na_fila.first[:args]).last
      expect(meta).not_to have_key(Autonomia::Agents::AgenteSoInforma::META)
      expect(turno.em_curso?(conversation.id)).to be(false)
    end

    it 'sem o sinal, a cadeia termina sem chamar a Atribuição' do
      ia_responde(fala, should: false)

      responder.perform
      entregar_os_pedacos!

      expect(respostas.count).to be > 1
      expect(contrato).not_to have_received(:avaliar_depois_da_fala)
    end

    it 'a cadeia parou no meio (uma pessoa assumiu): a Atribuição não é chamada' do
      ia_responde

      responder.perform
      conversation.update!(assignee: create(:user, account: account, role: :agent))
      entregar_os_pedacos!

      expect(contrato).not_to have_received(:avaliar_depois_da_fala)
    end
  end

  # O evento da cotação da Lia fica fora do #2154: com a flag, o sinal continua passando a conversa.
  describe Autonomia::Agents::Operate::ResponderAoEvento do
    let(:evento) do
      instance_double(Autonomia::Agents::Tools::Evento, tipo: 'falhou', run: nil, nota_do_sistema: 'A consulta falhou.',
                                                        publicado?: false, marca: 'evento-2154')
    end

    around { |example| with_modified_env(AI_HUMANIZE_DELIVERY: 'false') { example.run } }

    it 'com a flag ligada, o sinal no evento ainda passa a conversa, como antes', :aggregate_failures do
      ia_responde

      result = described_class.new(conversation: conversation, agent_inbox: agent_inbox, evento: evento).perform

      expect(result.status).to eq(:replied)
      expect(conversation.reload.additional_attributes.to_h).to have_key(Conversation::BOT_HANDOFF_WAITING_SINCE_KEY)
      expect(Autonomia::Agents::AgentEvent.handed_off.count).to eq(1)
      expect(Autonomia::Agents::AgentEvent.avisou_que_chama_alguem.count).to eq(0)
      expect(Autonomia::Agents::NotaDoEncaminhamento).to have_received(:postar).with(conversation)
      expect(contrato).not_to have_received(:avaliar_depois_da_fala)
    end
  end
end

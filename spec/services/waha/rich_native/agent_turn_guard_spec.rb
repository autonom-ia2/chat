require 'rails_helper'

RSpec::Matchers.define_negated_matcher :not_include, :include

# chat#1709 (aprovado pelo Rodrigo em 16/10/2026): o agente de IA e o que o recebimento da caixa WAHA grava.
# - O voto na enquete e a resposta ao convite são turnos do cliente (mensagem recebida, escondida na tela) e seguem o
#   caminho real do turno (gatilho, debounce, settle, Responder), com a Fase 2 dos agentes ligada.
# - A bolha "abra no celular" e a mensagem apagada pelo cliente não são respondidas; a apagada sai do histórico.
RSpec.describe Waha::RichNative::AgentTurnGuard, :um_turno do
  include_context 'with crm responsible agent'

  let(:inbox) do
    create(:channel_api, account: account, webhook_url: 'https://waha.example/webhooks/chatwoot/abc',
                         additional_attributes: { 'provider' => 'waha', 'session' => 's1' }).inbox
  end
  let(:consultas) { [] }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    contrato!
    clear_enqueued_jobs
    account.enable_features!(Waha::RichNative::FLAG)
    allow(Autonomia::Agents::Answerer).to receive(:new) do |agent:, query:, history:, **|
      consultas << { query: query, history: history }
      resposta = double('Answerer') # rubocop:disable RSpec/VerifiedDoubles
      allow(resposta).to receive(:answer).and_return(
        Autonomia::Agents::AnswerResult.new(reply: "Resposta de #{agent.name}.", confidence: 0.9, handoff: { should: false, reason: nil },
                                            used_knowledge: [], answered_from_knowledge: false)
      )
      resposta
    end
  end

  # A mensagem como Waha::RichNative::AiTurn.record! a deixa: recebida, do contato, escondida na tela, texto claro.
  def turno_do_voto(texto)
    message = create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :incoming, sender: contact,
                               content: texto, content_attributes: {})
    message.update_column(:content_attributes, { 'c2y_hidden' => true, 'poll_vote_applied_to' => 1 }) # rubocop:disable Rails/SkipsModelValidations
    message.reload
  end

  def ouvir(message)
    Autonomia::Agents::Operate::MessageListener.instance.message_created(Events::Base.new('message.created', Time.zone.now, message: message))
  end

  describe 'the vote and the event reply as a customer turn' do
    it 'reaches the AI through the normal path, as a customer message with the clear text' do
      voto = turno_do_voto("Votou na enquete 'Qual horário?': Tarde")

      expect { ouvir(voto) }.to have_enqueued_job(Autonomia::Agents::Operate::ReplyJob).with(conversation.id, voto.id)
      rodar_turno!

      expect(respostas.count).to eq(1)
      expect(consultas.sole[:query]).to include("Votou na enquete 'Qual horário?': Tarde")
      expect(consultas.sole[:history].last).to include(role: 'user', content: "Votou na enquete 'Qual horário?': Tarde")
    end

    it 'answers only the last choice when the customer changes the vote inside the debounce' do
      primeiro = turno_do_voto("Votou na enquete 'Qual horário?': Manhã")
      ouvir(primeiro)
      segundo = turno_do_voto("Votou na enquete 'Qual horário?': Tarde")
      ouvir(segundo)

      rodar_turno!

      expect(respostas.count).to eq(1)
      expect(consultas.sole[:query]).to include('Tarde')
    end

    it 'treats the reply to an event invitation the same way' do
      resposta = turno_do_voto("Respondeu ao convite 'Visita técnica': Vou")
      ouvir(resposta)

      rodar_turno!

      expect(respostas.count).to eq(1)
      expect(consultas.sole[:query]).to include("Respondeu ao convite 'Visita técnica': Vou")
    end
  end

  # Rodada de correção, item 15: o `content` do turno é só a escolha; a IA lê a pergunta pelo contexto.
  it 'gives the AI the question of a real vote turn, whose content is only the choice' do
    poll = create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :outgoing, content: 'Qual horário?')
    poll.update_column(:content_attributes, { 'poll_votes' => [{ 'sender_type' => 'Contact', 'sender_id' => contact.id, 'options' => ['Tarde'] }] }) # rubocop:disable Rails/SkipsModelValidations
    voto = turno_do_voto(Waha::RichNative::AiTurn.poll_text(account, poll, ['Tarde']))
    voto.update_column(:content_attributes, voto.content_attributes.merge(Waha::RichNative::AiTurn.choice('poll_vote', poll, ['Tarde']))) # rubocop:disable Rails/SkipsModelValidations
    completo = Waha::RichNative::AiTurn.full_text(account, voto.reload.content_attributes['c2y_ai_turn'])
    gatilho(voto)

    rodar_turno!

    expect(voto.content).not_to include('Qual horário?')
    # Um caminho só (revisão, risco 10): o texto completo vai no histórico, uma vez; a pergunta do turno é a da main.
    expect(consultas.sole[:history].last).to include(role: 'user', content: completo)
    expect(consultas.sole[:history].count { |item| item[:content].to_s.include?(completo) }).to eq(1)
    expect(consultas.sole[:query]).not_to include('Qual horário?')
  end

  describe 'the unsupported bubble ("open it on the phone")' do
    def sem_suporte
      create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :incoming, sender: contact,
                       content: 'Mensagem não suportada', content_attributes: { 'is_unsupported' => true })
    end

    it 'keeps the AI quiet and records skipped_mensagem_sem_suporte once per message, with the flag' do
      mensagem = sem_suporte
      gatilho(mensagem)
      rodar_turno!
      gatilho(mensagem)
      rodar_turno!

      expect(Autonomia::Agents::Answerer).not_to have_received(:new)
      expect(respostas).to be_empty
      eventos = Autonomia::Agents::AgentEvent.skipped_mensagem_sem_suporte.where(conversation_id: conversation.id)
      expect(eventos.pluck(:message_id)).to eq([mensagem.id])
      expect(Autonomia::Agents::AgentEvent::NAO_ATENDIMENTO_TYPES).to include('skipped_mensagem_sem_suporte')
    end

    it 'keeps the AI quiet on the view once notice and leaves it out of the history' do
      aviso = create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :incoming, sender: contact,
                               content: 'Você recebeu uma mensagem de visualização única.', content_attributes: {})
      aviso.update_column(:content_attributes, { 'view_once_unavailable' => true }) # rubocop:disable Rails/SkipsModelValidations
      gatilho(aviso)
      rodar_turno!

      expect(Autonomia::Agents::Answerer).not_to have_received(:new)
      expect(Autonomia::Agents::AgentEvent.skipped_mensagem_sem_suporte.pluck(:message_id)).to eq([aviso.id])

      gatilho(cliente_escreve('Recebeu?'))
      rodar_turno!
      expect(consultas.sole[:history].pluck(:content)).not_to include('Você recebeu uma mensagem de visualização única.')
    end

    it 'answers as in main without the flag' do
      account.disable_features!(Waha::RichNative::FLAG)
      gatilho(sem_suporte)

      rodar_turno!

      expect(respostas.count).to eq(1)
      expect(Autonomia::Agents::AgentEvent.skipped_mensagem_sem_suporte).to be_empty
    end
  end

  describe 'a burst with a real message' do
    it 'answers when the turn has a real message besides the unsupported one, without the deleted one in the history' do
      apagada = cliente_escreve('Mensagem apagada')
      apagada.update_column(:content_attributes, { 'deleted_by_contact_at' => Time.current.iso8601 }) # rubocop:disable Rails/SkipsModelValidations
      cliente_escreve('Olha o que mandei')
      sem = create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :incoming, sender: contact,
                             content: 'Mensagem não suportada', content_attributes: { 'is_unsupported' => true })
      gatilho(sem)

      rodar_turno!

      expect(respostas.count).to eq(1)
      expect(consultas.sole[:history].pluck(:content)).to include('Olha o que mandei').and(not_include('Mensagem apagada'))
      expect(Autonomia::Agents::AgentEvent.where(conversation_id: conversation.id)
                                          .where(event_type: %i[skipped_mensagem_sem_suporte skipped_mensagem_apagada])).to be_empty
    end
  end

  # Rodada de correção, itens 2 e 3: a bolha e o aviso não são turno. O listener não os dispara (o rastro sai por um job
  # próprio), e a pergunta da IA vem da última mensagem real, mesmo quando um settle antigo cai na bolha.
  describe 'bursts mixing a real message with the unsupported bubble' do
    def bolha
      create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :incoming, sender: contact,
                       content: 'Mensagem não suportada', content_attributes: { 'is_unsupported' => true })
    end

    def rodar_tudo!
      rodar_turno!
      rodar_turno!('Waha::RichNative::UnsupportedTurnJob')
    end

    it '[A, U]: the listener ignores U, and A is answered (query from A)' do
      texto = cliente_escreve('Qual o preço?')
      ouvir(texto)
      sem = bolha
      expect { ouvir(sem) }.not_to have_enqueued_job(Autonomia::Agents::Operate::ReplyJob)

      rodar_tudo!

      expect(respostas.count).to eq(1)
      expect(consultas.sole[:query]).to include('Qual o preço?').and(not_include('Mensagem não suportada'))
      # A IA respondeu ao turno: não houve silêncio, e o card "Quando a IA ficou calada" não conta a bolha.
      expect(Autonomia::Agents::AgentEvent.skipped_mensagem_sem_suporte).to be_empty
    end

    it '[U]: no turn, no answer, and the trace once per message' do
      sem = bolha
      ouvir(sem)
      ouvir(sem)

      rodar_tudo!

      expect(Autonomia::Agents::Answerer).not_to have_received(:new)
      expect(respostas).to be_empty
      expect(Autonomia::Agents::AgentEvent.skipped_mensagem_sem_suporte.pluck(:message_id)).to eq([sem.id])
    end

    it '[U, A]: A is answered' do
      ouvir(bolha)
      ouvir(cliente_escreve('Recebeu minha foto?'))

      rodar_tudo!

      expect(respostas.count).to eq(1)
      expect(consultas.sole[:query]).to include('Recebeu minha foto?').and(not_include('Mensagem não suportada'))
      expect(Autonomia::Agents::AgentEvent.skipped_mensagem_sem_suporte).to be_empty
    end

    it 'counts the bubble as a silence when a person answered it (the AI kept quiet for the whole turn)' do
      sem = bolha
      ouvir(sem)
      create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :outgoing, content: 'Pode mandar de novo?',
                       sender: create(:user, account: account))

      rodar_tudo!

      expect(Autonomia::Agents::AgentEvent.skipped_mensagem_sem_suporte.pluck(:message_id)).to eq([sem.id])
    end

    # Revisão, item 4: o rastro usa o mesmo filtro do voto retirado/trocado do settle (TurnKinds.turn_silence).
    def voto_retirado
      poll = create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :outgoing, content: 'Qual horário?')
      poll.update_column(:content_attributes, { 'poll_votes' => [{ 'sender_type' => 'Contact', 'sender_id' => contact.id, 'options' => [] }] }) # rubocop:disable Rails/SkipsModelValidations
      voto = turno_do_voto('Votou: Tarde')
      voto.update_column(:content_attributes, voto.content_attributes.merge(Waha::RichNative::AiTurn.choice('poll_vote', poll, ['Tarde']))) # rubocop:disable Rails/SkipsModelValidations
      voto
    end

    it 'counts the bubble as a silence when the only other message of the turn is a vote taken back' do
      voto_retirado
      sem = bolha

      Waha::RichNative::UnsupportedTurnJob.perform_now(conversation.id, sem.id, 'settle')

      expect(Autonomia::Agents::AgentEvent.skipped_mensagem_sem_suporte.pluck(:message_id)).to eq([sem.id])
    end

    it 'records one silence per turn when the settle already silenced it ([vote taken back, bubble])' do
      ouvir(voto_retirado)
      ouvir(bolha)

      rodar_tudo!

      expect(respostas).to be_empty
      expect(Autonomia::Agents::AgentEvent.where(conversation_id: conversation.id)
                                          .where(event_type: %i[skipped_mensagem_sem_suporte skipped_escolha_retirada]).count).to eq(1)
    end

    it 'ignores the view once notice too' do
      aviso = create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :incoming, sender: contact,
                               content: 'Você recebeu uma mensagem de visualização única.', content_attributes: {})
      aviso.update_column(:content_attributes, { 'view_once_unavailable' => true }) # rubocop:disable Rails/SkipsModelValidations

      expect { ouvir(aviso) }.not_to have_enqueued_job(Autonomia::Agents::Operate::ReplyJob)
    end

    it 'takes the query from the real message even when the settle lands on the bubble' do
      cliente_escreve('Quero agendar')
      gatilho(bolha)

      rodar_turno!

      expect(respostas.count).to eq(1)
      expect(consultas.sole[:query]).to include('Quero agendar').and(not_include('Mensagem não suportada'))
    end

    it 'keeps main without the flag: the bubble triggers the turn' do
      account.disable_features!(Waha::RichNative::FLAG)

      expect { ouvir(bolha) }.to have_enqueued_job(Autonomia::Agents::Operate::ReplyJob)
    end
  end

  describe 'a vote taken back inside the debounce' do
    it 'does not answer when the choice of the turn is no longer stored on the poll' do
      poll = create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :outgoing, content: 'Qual horário?')
      poll.update_column(:content_attributes, { 'poll_votes' => [{ 'sender_type' => 'Contact', 'sender_id' => contact.id, 'options' => [] }] }) # rubocop:disable Rails/SkipsModelValidations
      voto = turno_do_voto("Votou na enquete 'Qual horário?': Tarde")
      voto.update_column(:content_attributes, voto.content_attributes.merge( # rubocop:disable Rails/SkipsModelValidations
                                                'c2y_ai_turn' => { 'kind' => 'poll_vote', 'target_id' => poll.id, 'choice' => ['Tarde'] }
                                              ))
      gatilho(voto)

      rodar_turno!

      expect(Autonomia::Agents::Answerer).not_to have_received(:new)
      expect(respostas).to be_empty
      expect(Autonomia::Agents::AgentEvent.skipped_escolha_retirada.pluck(:message_id)).to eq([voto.id])
    end

    it 'drops only the vote that no longer counts and answers the text of the same burst' do
      poll = create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :outgoing, content: 'Qual horário?')
      poll.update_column(:content_attributes, { 'poll_votes' => [{ 'sender_type' => 'Contact', 'sender_id' => contact.id, 'options' => [] }] }) # rubocop:disable Rails/SkipsModelValidations
      cliente_escreve('Prefiro falar com alguém')
      voto = turno_do_voto("Votou na enquete 'Qual horário?': Tarde")
      voto.update_column(:content_attributes, voto.content_attributes.merge( # rubocop:disable Rails/SkipsModelValidations
                                                'c2y_ai_turn' => { 'kind' => 'poll_vote', 'target_id' => poll.id, 'choice' => ['Tarde'] }
                                              ))
      gatilho(voto)

      rodar_turno!

      expect(respostas.count).to eq(1)
      expect(consultas.sole[:query]).to include('Prefiro falar com alguém').and(not_include('Votou na enquete'))
      expect(consultas.sole[:history].pluck(:content)).not_to include("Votou na enquete 'Qual horário?': Tarde")
      expect(Autonomia::Agents::AgentEvent.skipped_escolha_retirada).to be_empty
    end
  end

  describe 'the message deleted by the customer' do
    def apagar!(message)
      message.update_column(:content_attributes, { 'deleted_by_contact_at' => Time.current.iso8601 }) # rubocop:disable Rails/SkipsModelValidations
      message
    end

    it 'is not answered, leaves skipped_mensagem_apagada and keeps the turn ownership (deliberate silence)' do
      apagada = apagar!(cliente_escreve('Quero cancelar'))
      gatilho(apagada)

      rodar_turno!

      expect(Autonomia::Agents::Answerer).not_to have_received(:new)
      expect(respostas).to be_empty
      expect(Autonomia::Agents::AgentEvent.skipped_mensagem_apagada.pluck(:message_id)).to eq([apagada.id])
      chave = Autonomia::Agents::Operate::PosseDoTurno.chave(conversation.id, apagada.id, vinculo_da_porta.id)
      expect(Redis::Alfred.get(chave)).to be_present
    end

    # Item 9 (alinhado com o Max e o Agentes IA): a regra da apagada vale em qualquer caixa em que a chave exista; ela
    # só existe quando algo a gravou (o conector, ou o #1702b na Cloud).
    it 'is not answered without the flag either, when the key is there' do
      account.disable_features!(Waha::RichNative::FLAG)
      apagada = apagar!(cliente_escreve('Quero cancelar'))
      gatilho(apagada)
      rodar_turno!
      expect(respostas).to be_empty
      expect(Autonomia::Agents::AgentEvent.skipped_mensagem_apagada.pluck(:message_id)).to eq([apagada.id])
    end

    it 'is not answered in an inbox that is not the WAHA one either' do
      inbox.channel.update!(additional_attributes: { 'provider' => 'outro' })
      gatilho(apagar!(cliente_escreve('Quero cancelar')))
      rodar_turno!
      expect(respostas).to be_empty
      expect(Autonomia::Agents::AgentEvent.skipped_mensagem_apagada.count).to eq(1)
    end

    it 'leaves the history the AI reads' do
      apagada = cliente_escreve('Quero cancelar')
      apagada.update_column(:content_attributes, { 'deleted_by_contact_at' => Time.current.iso8601 }) # rubocop:disable Rails/SkipsModelValidations
      gatilho(cliente_escreve('Qual o horário de amanhã?'))

      rodar_turno!

      expect(respostas.count).to eq(1)
      expect(consultas.sole[:history].pluck(:content)).not_to include('Quero cancelar')
    end
  end

  # Revisão do Agentes IA (sobre 0d2a9c6325): os pontos que valiam no HEAD.
  describe 'review of the Agentes IA team' do
    def bolha
      create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :incoming, sender: contact,
                       content: 'Mensagem não suportada', content_attributes: { 'is_unsupported' => true })
    end

    def voto_retirado
      poll = create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :outgoing, content: 'Qual horário?')
      poll.update_column(:content_attributes, { 'poll_votes' => [{ 'sender_type' => 'Contact', 'sender_id' => contact.id, 'options' => [] }] }) # rubocop:disable Rails/SkipsModelValidations
      voto = turno_do_voto('Votou: Tarde')
      voto.update_column(:content_attributes, voto.content_attributes.merge(Waha::RichNative::AiTurn.choice('poll_vote', poll, ['Tarde']))) # rubocop:disable Rails/SkipsModelValidations
      voto
    end

    it 'counts only real interactions in the history window: 25 real messages stay with 3 hidden ones among them' do
      inicio = 2.hours.ago
      reais = (1..25).map do |numero|
        message = cliente_escreve("real #{numero}")
        message.update_column(:created_at, inicio + numero.minutes) # rubocop:disable Rails/SkipsModelValidations
        message
      end
      escondidas = [bolha, turno_do_voto('Votou: Sim'), cliente_escreve('apagada')]
      escondidas.last.update_column(:content_attributes, { 'deleted_by_contact_at' => Time.current.iso8601 }) # rubocop:disable Rails/SkipsModelValidations
      escondidas.each_with_index { |message, index| message.update_column(:created_at, inicio + (20 + index).minutes + 30.seconds) } # rubocop:disable Rails/SkipsModelValidations
      gatilho(reais.last)

      rodar_turno!

      conteudos = consultas.sole[:history].pluck(:content)
      expect(conteudos).to include(*reais.map(&:content))
    end

    it 'silence 17 keeps the turn ownership and disarms the waiting time the hidden vote armed' do
      conversation.update!(waiting_since: nil)
      voto = voto_retirado
      expect(conversation.reload.waiting_since).to be_present
      conversation.update_column(:updated_at, 1.hour.ago) # rubocop:disable Rails/SkipsModelValidations
      gatilho(voto)

      rodar_turno!

      expect(conversation.reload.updated_at).to be > 1.minute.ago

      expect(respostas).to be_empty
      expect(Autonomia::Agents::AgentEvent.skipped_escolha_retirada.pluck(:message_id)).to eq([voto.id])
      expect(conversation.reload.waiting_since).to be_nil
      chave = Autonomia::Agents::Operate::PosseDoTurno.chave(conversation.id, voto.id, vinculo_da_porta.id)
      expect(Redis::Alfred.get(chave)).to be_present
    end

    it 'silence 17 does not clear a waiting time a new customer message changed in the meantime (compare-and-clear)' do
      conversation.update!(waiting_since: nil)
      voto = voto_retirado
      depois = 1.minute.from_now.change(usec: 0)
      allow(Conversation).to receive(:where).and_call_original
      allow(Conversation).to receive(:where).with(hash_including(:waiting_since)).and_wrap_original do |original, *args|
        Conversation.where(id: conversation.id).update_all(waiting_since: depois) # rubocop:disable Rails/SkipsModelValidations
        original.call(*args)
      end
      gatilho(voto)

      rodar_turno!

      expect(Autonomia::Agents::AgentEvent.skipped_escolha_retirada.count).to eq(1)
      expect(conversation.reload.waiting_since).to eq(depois)
    end

    it 'tells the screen when silence 17 clears the waiting time' do
      conversation.update!(waiting_since: nil)
      voto = voto_retirado
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original
      gatilho(voto)

      rodar_turno!

      expect(Rails.configuration.dispatcher).to have_received(:dispatch)
        .with(Events::Types::CONVERSATION_UPDATED, anything, hash_including(changed_attributes: hash_including('waiting_since')))
    end

    it 'silence 17 keeps a waiting time armed before the vote' do
      antes = 1.hour.ago.change(usec: 0)
      voto = voto_retirado
      # Armado antes do voto (uma mensagem real anterior): o voto não o trocou.
      conversation.update!(waiting_since: antes)
      gatilho(voto)

      rodar_turno!

      expect(conversation.reload.waiting_since).to eq(antes)
    end

    it 'sends an unexpected guard error to the tracker without its message, and answers as in main' do
      tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
      reported = nil
      allow(ChatwootExceptionTracker).to receive(:new) { |error, **| (reported = error) && tracker }
      allow(Waha::RichNative::TurnKinds).to receive(:turn_silence)
        .and_raise(ActiveRecord::ConnectionNotEstablished, 'texto do cliente: Quero cancelar')
      gatilho(cliente_escreve('Oi'))

      rodar_turno!

      expect(respostas.count).to eq(1)
      expect(tracker).to have_received(:capture_exception)
      expect(reported).to be_a(ActiveRecord::ConnectionNotEstablished)
      expect(reported.message).not_to include('Quero cancelar')
    end

    it 'does not lose the silence when checking the event fails' do
      allow(ChatwootExceptionTracker).to receive(:new).and_return(instance_double(ChatwootExceptionTracker, capture_exception: true))
      allow_any_instance_of(Autonomia::Agents::Agent).to receive(:events).and_raise(ActiveRecord::ConnectionNotEstablished) # rubocop:disable RSpec/AnyInstance
      gatilho(voto_retirado)

      expect { rodar_turno! }.not_to raise_error
      expect(respostas).to be_empty
    end

    it 'gives the AI the notice of a photo that failed to download, as the customer turn' do
      aviso = Waha::RichNative::Inbound::MediaFailed.notice(account, 'image')
      message = create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :incoming, sender: contact,
                                 content: aviso, content_attributes: { 'media_unavailable' => { 'kind' => 'image', 'reason' => 'download_failed' } })
      gatilho(message)

      rodar_turno!

      expect(respostas.count).to eq(1)
      expect(consultas.sole[:query]).to include(aviso)
    end

    it 'never answers nor records 15-17 in a conversation assigned to a person' do
      conversation.update!(assignee: admin)
      gatilho(bolha)
      gatilho(voto_retirado)

      rodar_turno!

      expect(respostas).to be_empty
      expect(Autonomia::Agents::AgentEvent.where(conversation_id: conversation.id)
                                          .where(event_type: %i[skipped_mensagem_sem_suporte skipped_mensagem_apagada skipped_escolha_retirada]))
        .to be_empty
    end

    # Decisão documentada: a bolha sozinha não tem o que responder, também fora do horário; o guard cala o turno antes da
    # porta de engajamento (sem passar a conversa às pessoas por causa da bolha).
    it 'records silence 15 for a bubble-only turn even outside the schedule' do
      agente_da_porta.update!(config: { 'response_window' => 'business_hours' })
      inbox.update!(working_hours_enabled: true)
      allow_any_instance_of(Inbox).to receive(:out_of_office?).and_return(true) # rubocop:disable RSpec/AnyInstance
      sem = bolha
      gatilho(sem)

      rodar_turno!

      expect(respostas).to be_empty
      expect(Autonomia::Agents::AgentEvent.skipped_mensagem_sem_suporte.pluck(:message_id)).to eq([sem.id])
      expect(Autonomia::Agents::AgentEvent.skipped_schedule).to be_empty
    end

    context 'with the vote on the plan B of the Hybrid (Cloud inbox)' do
      let(:inbox) do
        create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                  validate_provider_config: false).inbox
      end

      it 'answers the vote through the Responder, with the question in the history' do
        poll = create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :outgoing, content: 'Qual horário?')
        votos = [{ 'sender_type' => 'Contact', 'sender_id' => contact.id, 'options' => ['Tarde'] }]
        poll.update_column(:content_attributes, { 'poll_votes' => votos }) # rubocop:disable Rails/SkipsModelValidations
        voto = turno_do_voto(Waha::RichNative::AiTurn.poll_text(account, poll, ['Tarde']))
        voto.update_column(:content_attributes, voto.content_attributes.merge(Waha::RichNative::AiTurn.choice('poll_vote', poll, ['Tarde']))) # rubocop:disable Rails/SkipsModelValidations
        gatilho(voto)

        rodar_turno!

        expect(respostas.count).to eq(1)
        completo = Waha::RichNative::AiTurn.full_text(account, voto.reload.content_attributes['c2y_ai_turn'])
        expect(consultas.sole[:history].last[:content]).to eq(completo)
      end
    end
  end

  # Item 9: na Cloud oficial (e no híbrido em coexistência), o #1702b grava `deleted_by_contact_at` mantendo o texto. A
  # mensagem é marcada à mão aqui, como ele faria.
  describe 'the message deleted by the customer on the official Cloud inbox' do
    let(:inbox) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                validate_provider_config: false).inbox
    end

    def apagar!(message)
      message.update_column(:content_attributes, { 'deleted_by_contact_at' => Time.current.iso8601 }) # rubocop:disable Rails/SkipsModelValidations
      message
    end

    it 'keeps the AI quiet on a turn with only the deleted message (silence 16)' do
      apagada = apagar!(cliente_escreve('Quero cancelar'))
      gatilho(apagada)

      rodar_turno!

      expect(respostas).to be_empty
      expect(Autonomia::Agents::AgentEvent.skipped_mensagem_apagada.pluck(:message_id)).to eq([apagada.id])
    end

    it 'answers the text of a turn with a text and a deleted message, without the deleted one' do
      cliente_escreve('Qual o horário de amanhã?')
      apagada = apagar!(cliente_escreve('Quero cancelar'))
      gatilho(apagada)

      rodar_turno!

      expect(respostas.count).to eq(1)
      expect(consultas.sole[:query]).to include('Qual o horário de amanhã?').and(not_include('Quero cancelar'))
      expect(consultas.sole[:history].pluck(:content)).not_to include('Quero cancelar')
    end

    it 'is identical to main without the key' do
      account.disable_features!(Waha::RichNative::FLAG)
      gatilho(cliente_escreve('Quero cancelar'))

      rodar_turno!

      expect(respostas.count).to eq(1)
      expect(consultas.sole[:history].pluck(:content)).to include('Quero cancelar')
      expect(Autonomia::Agents::AgentEvent.where(event_type: %i[skipped_mensagem_apagada skipped_mensagem_sem_suporte skipped_escolha_retirada]))
        .to be_empty
    end
  end

  # Item 8, decisão do Rodrigo: a edição do cliente NÃO é turno (a IA não responde a ela), mas a IA usa o texto novo.
  describe 'the customer edit' do
    it 'keeps the original in the history with the new text, opens no turn, and the next turn sees the new text' do
      inbox.channel.update!(additional_attributes: inbox.channel.additional_attributes.merge('account_token_owner_user_id' => admin.id))
      original = cliente_escreve('Meu carro é 2002')
      Current.user = admin
      edicao = conversation.messages.create!(account: account, inbox: inbox, message_type: :incoming, sender: contact,
                                             content: "Meu carro é 2022\n\n✏️ *Editado no WhatsApp*",
                                             content_attributes: { in_reply_to: original.id,
                                                                   waha_edit: { text: 'Meu carro é 2022', edited_wa_id: 'W1', from_me: false } })
      Current.user = nil

      # (a) a original fica, com o texto novo, e não escondida; só o evento da edição vira atividade escondida.
      expect(original.reload.content).to eq('Meu carro é 2022')
      expect(original.content_attributes).not_to have_key('c2y_hidden')
      expect(edicao.reload).to be_activity
      expect(edicao.content_attributes).to include('c2y_hidden' => true, 'edit_applied_to' => original.id)

      # (b) a edição não abre turno.
      expect { ouvir(edicao) }.not_to have_enqueued_job(Autonomia::Agents::Operate::ReplyJob)

      # (c) no turno seguinte, a IA lê o texto novo.
      gatilho(cliente_escreve('Quanto custa o seguro?'))
      rodar_turno!

      historico = consultas.sole[:history].pluck(:content)
      expect(historico).to include('Meu carro é 2022')
      expect(historico.join).not_to include('2002')
    ensure
      Current.user = nil
    end
  end

  # Testador da IA, B1: votos alternados com o mesmo valor do atual não ficam todos no histórico.
  it 'keeps one vote in the history after 26 alternating votes among 25 real messages' do
    poll = create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :outgoing, content: 'Qual horário?')
    inicio = 3.hours.ago
    (1..25).each do |numero|
      cliente_escreve("real #{numero}").update_column(:created_at, inicio + (numero * 2).minutes) # rubocop:disable Rails/SkipsModelValidations
    end
    titulos = (1..26).map { |numero| numero.even? ? 'Tarde' : 'Manhã' }
    titulos.each_with_index do |titulo, indice|
      voto = turno_do_voto("Votou: #{titulo}")
      voto.update_columns(created_at: inicio + ((indice * 2) + 1).minutes, # rubocop:disable Rails/SkipsModelValidations
                          content_attributes: voto.content_attributes.merge(Waha::RichNative::AiTurn.choice('poll_vote', poll, [titulo])))
    end
    poll.update_column(:content_attributes, { 'poll_votes' => [{ 'sender_type' => 'Contact', 'sender_id' => contact.id, 'options' => ['Tarde'] }] }) # rubocop:disable Rails/SkipsModelValidations
    gatilho(cliente_escreve('E agora?'))

    rodar_turno!

    votos = consultas.sole[:history].count { |item| item[:content].to_s.end_with?(': Tarde', ': Manhã') }
    expect(votos).to eq(1)
  end
end

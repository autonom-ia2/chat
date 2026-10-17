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

    it 'is answered as in main without the flag' do
      account.disable_features!(Waha::RichNative::FLAG)
      gatilho(apagar!(cliente_escreve('Quero cancelar')))
      rodar_turno!
      expect(respostas.count).to eq(1)
      expect(consultas.last[:history].pluck(:content)).to include('Quero cancelar')
    end

    it 'is answered as in main in an inbox that is not the WAHA one' do
      inbox.channel.update!(additional_attributes: { 'provider' => 'outro' })
      gatilho(apagar!(cliente_escreve('Quero cancelar')))
      rodar_turno!
      expect(respostas.count).to eq(1)
      expect(Autonomia::Agents::AgentEvent.skipped_mensagem_apagada).to be_empty
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
end

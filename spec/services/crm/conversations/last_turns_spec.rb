require 'rails_helper'

RSpec.describe Crm::Conversations::LastTurns do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create_crm_inbox(account: account, members: [admin]) }
  let(:bot) { create(:agent_bot, account: account) }

  def create_conversation
    contact = account.contacts.create!(name: "Lead #{SecureRandom.hex(3)}", phone_number: "+55119#{rand(10_000_000..99_999_999)}")
    create_crm_conversation(account: account, inbox: inbox, contact: contact)
  end

  def message(conversation, type, at, **attrs)
    conversation.messages.create!(
      account: account, inbox: inbox, content: 'x', message_type: type, private: false, created_at: at,
      sender: type == :incoming ? conversation.contact : admin, **attrs
    )
  end

  def turn_for(conversation)
    described_class.for(card: [conversation.id])[:card]
  end

  it 'marca o cliente esperando quando a última mensagem real é dele' do
    conversation = create_conversation
    message(conversation, :outgoing, 3.days.ago)
    last = message(conversation, :incoming, 2.days.ago)

    turn = turn_for(conversation)

    expect(turn.customer_waiting).to be(true)
    expect(turn.waiting_since).to be_within(1.second).of(last.created_at)
    expect(turn.last_message_at).to be_within(1.second).of(last.created_at)
  end

  it 'não marca espera quando respondemos depois, nem conta nota privada ou atividade' do
    conversation = create_conversation
    message(conversation, :incoming, 3.days.ago)
    reply = message(conversation, :outgoing, 2.days.ago)
    message(conversation, :outgoing, 1.day.ago, private: true)
    message(conversation, :activity, 1.hour.ago)

    turn = turn_for(conversation)

    expect(turn.customer_waiting).to be(false)
    expect(turn.waiting_since).to be_nil
    expect(turn.last_message_at).to be_within(1.second).of(reply.created_at)
  end

  # Mensagem automática do Chatwoot (saudação, ausência, pedido de e-mail, pesquisa) é `template`: não é
  # resposta a ninguém. O waiting_since do próprio Chatwoot também não a trata como resposta.
  it 'não deixa mensagem automática (template) fechar a espera do cliente' do
    conversation = create_conversation
    pergunta = message(conversation, :incoming, 2.hours.ago)
    message(conversation, :template, 1.hour.ago)

    turn = turn_for(conversation)

    expect(turn.customer_waiting).to be(true)
    expect(turn.last_message_at).to be_within(1.second).of(pergunta.created_at)
  end

  describe 'saída que não é resposta (mesmo critério do waiting_since do Chatwoot)' do
    it 'regra de automação depois da pergunta não fecha a espera' do
      conversation = create_conversation
      pergunta = message(conversation, :incoming, 2.hours.ago)
      message(conversation, :outgoing, 1.hour.ago, content_attributes: { automation_rule_id: 7 })

      turn = turn_for(conversation)

      expect(turn.customer_waiting).to be(true)
      expect(turn.waiting_since).to be_within(1.second).of(pergunta.created_at)
    end

    it 'campanha depois da pergunta não fecha a espera, mas conta como atividade da conversa' do
      conversation = create_conversation
      message(conversation, :incoming, 2.days.ago)
      campanha = message(conversation, :outgoing, 1.hour.ago, additional_attributes: { campaign_id: 3 })
      message(conversation, :outgoing, 30.minutes.ago, additional_attributes: { whatsapp_api_campaign_id: 9 })

      turn = turn_for(conversation)

      expect(turn.customer_waiting).to be(true)
      expect(turn.last_message_at).to be > campanha.created_at
    end

    it 'mensagem que falhou no envio não fecha a espera' do
      conversation = create_conversation
      message(conversation, :incoming, 2.hours.ago)
      message(conversation, :outgoing, 1.hour.ago, status: :failed)

      expect(turn_for(conversation).customer_waiting).to be(true)
    end

    # #1377: com a passagem pendente, o robô segue respondendo, mas o cliente espera o time.
    it 'com a passagem do robô para pessoa pendente, resposta do robô não fecha a espera; a de pessoa fecha' do
      conversation = create_conversation
      conversation.update!(additional_attributes: { ConversationBotHandoff::BOT_HANDOFF_WAITING_SINCE_KEY => 3.hours.ago.iso8601 })
      message(conversation, :incoming, 2.hours.ago)
      message(conversation, :outgoing, 1.hour.ago, sender: bot)

      expect(turn_for(conversation).customer_waiting).to be(true)

      message(conversation, :outgoing, 30.minutes.ago)

      expect(turn_for(conversation).customer_waiting).to be(false)
    end

    it 'sem passagem pendente, a resposta do robô fecha a espera' do
      conversation = create_conversation
      message(conversation, :incoming, 2.hours.ago)
      message(conversation, :outgoing, 1.hour.ago, sender: bot)

      expect(turn_for(conversation).customer_waiting).to be(false)
    end
  end

  # O importador de histórico grava em segundos inteiros: entrada e saída podem ter o mesmo horário. Desempata a
  # ordem de gravação (id).
  describe 'empate de horário' do
    let(:at) { 2.hours.ago.change(usec: 0) }

    it 'saída gravada depois da entrada, no mesmo segundo, responde' do
      conversation = create_conversation
      message(conversation, :incoming, at)
      message(conversation, :outgoing, at)

      expect(turn_for(conversation).customer_waiting).to be(false)
    end

    it 'entrada gravada depois da saída, no mesmo segundo, espera' do
      conversation = create_conversation
      message(conversation, :outgoing, at)
      message(conversation, :incoming, at)

      expect(turn_for(conversation).customer_waiting).to be(true)
    end
  end

  # O cliente pergunta no WhatsApp; nós mandamos qualquer coisa noutra conversa do card. Ele continua esperando.
  it 'conta por conversa: resposta noutra conversa não fecha a espera desta' do
    a = create_conversation
    b = create_conversation
    pergunta = message(a, :incoming, 5.days.ago)
    nossa = message(b, :outgoing, 1.day.ago)

    turns = described_class.for(um: [a.id, b.id], outro: [], nada: [nil])

    expect(turns[:um].customer_waiting).to be(true)
    expect(turns[:um].waiting_since).to be_within(1.second).of(pergunta.created_at)
    expect(turns[:um].last_message_at).to be_within(1.second).of(nossa.created_at)
    expect(turns[:outro].last_message_at).to be_nil
    expect(turns[:outro].customer_waiting).to be(false)
    expect(turns[:nada].last_message_at).to be_nil
  end

  it 'com duas conversas esperando, conta desde a fala mais antiga sem resposta' do
    a = create_conversation
    b = create_conversation
    antiga = message(a, :incoming, 4.days.ago)
    message(b, :incoming, 1.day.ago)

    turn = described_class.for(card: [a.id, b.id])[:card]

    expect(turn.waiting_since).to be_within(1.second).of(antiga.created_at)
  end

  it 'lê o lote inteiro sem uma consulta por conversa' do
    conversations = Array.new(4) { create_conversation }
    conversations.each do |c|
      message(c, :incoming, 2.days.ago)
      message(c, :outgoing, 1.day.ago)
    end
    keys = conversations.index_by(&:id).transform_values { |c| [c.id] }

    queries = 0
    counter = ->(*, payload) { queries += 1 if payload[:sql].include?('messages') }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') { described_class.for(keys) }

    expect(queries).to be <= 2
  end
end

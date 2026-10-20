require 'rails_helper'

RSpec.describe Crm::Conversations::LastTurns do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create_crm_inbox(account: account, members: [admin]) }

  def create_conversation
    contact = account.contacts.create!(name: "Lead #{SecureRandom.hex(3)}", phone_number: "+55119#{rand(10_000_000..99_999_999)}")
    create_crm_conversation(account: account, inbox: inbox, contact: contact)
  end

  def message(conversation, type, at, private: false)
    conversation.messages.create!(
      account: account, inbox: inbox, content: 'x', message_type: type, private: private, created_at: at,
      sender: type == :incoming ? conversation.contact : admin
    )
  end

  it 'marca o cliente esperando quando a última mensagem real é dele' do
    conversation = create_conversation
    message(conversation, :outgoing, 3.days.ago)
    last = message(conversation, :incoming, 2.days.ago)

    turn = described_class.for(card: [conversation.id])[:card]

    expect(turn.customer_waiting).to be(true)
    expect(turn.last_message_at).to be_within(1.second).of(last.created_at)
  end

  it 'não marca espera quando respondemos depois, nem conta nota privada ou atividade' do
    conversation = create_conversation
    message(conversation, :incoming, 3.days.ago)
    reply = message(conversation, :outgoing, 2.days.ago)
    message(conversation, :outgoing, 1.day.ago, private: true)
    message(conversation, :activity, 1.hour.ago)

    turn = described_class.for(card: [conversation.id])[:card]

    expect(turn.customer_waiting).to be(false)
    expect(turn.last_message_at).to be_within(1.second).of(reply.created_at)
  end

  # Mensagem automática do Chatwoot (saudação, ausência, pedido de e-mail, pesquisa) é `template`: não é
  # resposta a ninguém. O waiting_since do próprio Chatwoot também não a trata como resposta.
  it 'não deixa mensagem automática (template) fechar a espera do cliente' do
    conversation = create_conversation
    pergunta = message(conversation, :incoming, 2.hours.ago)
    message(conversation, :template, 1.hour.ago)

    turn = described_class.for(card: [conversation.id])[:card]

    expect(turn.customer_waiting).to be(true)
    expect(turn.last_message_at).to be_within(1.second).of(pergunta.created_at)
  end

  it 'junta as conversas de cada chave e devolve vazio para chave sem mensagem' do
    a = create_conversation
    b = create_conversation
    message(a, :incoming, 5.days.ago)
    message(b, :outgoing, 1.day.ago)

    turns = described_class.for(um: [a.id, b.id], outro: [], nada: [nil])

    expect(turns[:um].customer_waiting).to be(false)
    expect(turns[:outro].last_message_at).to be_nil
    expect(turns[:outro].customer_waiting).to be(false)
    expect(turns[:nada].last_message_at).to be_nil
  end

  it 'lê o lote inteiro sem uma consulta por conversa' do
    conversations = Array.new(4) { create_conversation }
    conversations.each { |c| message(c, :incoming, 1.day.ago) }
    keys = conversations.index_by(&:id).transform_values { |c| [c.id] }

    queries = 0
    counter = ->(*, payload) { queries += 1 if payload[:sql].include?('"messages"') }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') { described_class.for(keys) }

    expect(queries).to be <= 2
  end
end

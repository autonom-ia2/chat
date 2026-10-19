require 'rails_helper'

# chat#1709: `c2y_revocable` (toda mensagem da lista) e `whatsapp_api_group` (toda conversa da lista) não podem
# consultar o banco por item. Conta só as consultas feitas DENTRO dos dois predicados: o total não cresce com a lista.
RSpec.describe 'WAHA rich native fields without N+1', type: :request do
  let(:channel) { create(:channel_api, additional_attributes: { 'provider' => 'waha', 'session' => 's1' }) }
  let(:account) { channel.account }
  let(:agent) { create(:user, account: account, role: :administrator) }

  before { account.enable_features!(Waha::RichNative::FLAG) }

  # Consultas SQL feitas dentro de `target.method` durante o bloco.
  def queries_inside(target, method)
    count = 0
    counter = ->(*, payload) { count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) }
    allow(target).to receive(method).and_wrap_original do |original, *args|
      ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') { original.call(*args) }
    end
    yield
    count
  end

  def conversation_with_messages(total)
    create(:conversation, inbox: channel.inbox, account: account).tap do |conversation|
      create_list(:message, total, message_type: :outgoing, conversation: conversation, inbox: channel.inbox, account: account)
    end
  end

  def messages_index_queries(total)
    conversation = conversation_with_messages(total)
    queries_inside(Waha::RichNative::Revocable, :for) do
      get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages", headers: agent.create_new_auth_token
      flags = response.parsed_body['payload'].pluck('c2y_revocable')
      expect(flags.size).to eq(total)
      expect(flags).to all(be(true))
    end
  end

  def create_group_conversations(total)
    total.times do
      contact = create(:contact, account: account, identifier: "#{SecureRandom.hex(6)}@g.us")
      create(:conversation, inbox: channel.inbox, account: account, contact: contact, assignee: agent)
    end
  end

  def conversations_index_queries(total)
    create_group_conversations(total)
    queries_inside(Waha::RichNative, :api_group?) do
      get "/api/v1/accounts/#{account.id}/conversations", params: { status: 'open' }, headers: agent.create_new_auth_token
      groups = response.parsed_body.dig('data', 'payload').pluck('whatsapp_api_group')
      expect(groups.size).to be >= total
      expect(groups).to all(be(true))
    end
  end

  it 'c2y_revocable: the message list does not query per message' do
    few = messages_index_queries(2)
    many = messages_index_queries(8)

    expect(many).to eq(few)
  end

  it 'whatsapp_api_group: the conversation list does not query per conversation' do
    expect(conversations_index_queries(2)).to eq(0)
    expect(conversations_index_queries(6)).to eq(0)
  end
end

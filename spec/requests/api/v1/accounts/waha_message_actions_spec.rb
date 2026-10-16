require 'rails_helper'

# chat#1709 (fase 3): reagir e editar pelo painel na caixa WAHA comum. O chat2you grava e manda ao webhook da caixa um
# evento próprio, que o conector customizado leva ao motor.
RSpec.describe 'WAHA message actions API', type: :request do
  let(:engine) { 'https://waha.example' }
  let(:channel) do
    create(:channel_api, webhook_url: "#{engine}/webhooks/chatwoot/abc", additional_attributes: { 'provider' => 'waha', 'session' => 's1' })
  end
  let(:account) { channel.account }
  let(:agent) { create(:user, account: account, role: :administrator) }
  let(:conversation) { create(:conversation, inbox: channel.inbox, account: account) }
  let(:actions) { %w[react edit] }
  let(:events) { [] }

  around { |example| with_modified_env(WAHA_RICH_NATIVE_ENGINES: "#{engine}/") { example.run } }

  before do
    allow(Waha::EngineCapabilities).to receive(:actions) { |url| url == "#{engine}/" ? actions : [] }
    allow(WebhookJob).to receive(:perform_later) { |_url, payload, kind, **| events << payload if kind == :api_inbox_webhook }
    account.enable_features!(Waha::RichNative::FLAG)
  end

  def message_url(message, action)
    "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message.id}/#{action}"
  end

  def ours(content = 'Até amanhã', **attrs)
    create(:message, { message_type: :outgoing, content: content, conversation: conversation, inbox: channel.inbox, account: account,
                       sender: agent }.merge(attrs)).tap { events.clear }
  end

  def react(message, emoji)
    post message_url(message, 'reaction'), params: { emoji: emoji }, headers: agent.create_new_auth_token, as: :json
  end

  def edit(message, content)
    patch message_url(message, 'content'), params: { content: content }, headers: agent.create_new_auth_token, as: :json
  end

  describe 'reaction' do
    it 'stores one reaction per agent and sends the event to the connector; an empty emoji removes it' do
      customer = create(:message, message_type: :incoming, content: 'oi', conversation: conversation, inbox: channel.inbox,
                                  account: account)
      events.clear

      react(customer, '👍')
      react(customer, '❤️')

      expect(response).to have_http_status(:ok)
      reactions = customer.reload.content_attributes['reactions']
      expect(reactions.map { |reaction| reaction.slice('emoji', 'by', 'user_id') })
        .to eq([{ 'emoji' => '❤️', 'by' => 'agent', 'user_id' => agent.id }])
      expect(events.last).to include(event: 'c2y_message_reaction', id: customer.id, c2y_reaction: { emoji: '❤️' })

      react(customer, '')
      expect(customer.reload.content_attributes['reactions']).to eq([])
      expect(events.last[:c2y_reaction]).to eq(emoji: '')
    end

    it 'refuses more than one emoji, notes and activities' do
      react(ours, '👍👍')
      expect(response).to have_http_status(:unprocessable_entity)

      react(ours('nota', private: true), '👍')
      expect(response).to have_http_status(:unprocessable_entity)
      expect(events).to be_empty
    end

    it 'is forbidden without the flag or without the engine action' do
      message = ours
      account.disable_features!(Waha::RichNative::FLAG)
      react(message, '👍')
      expect(response).to have_http_status(:forbidden)

      account.enable_features!(Waha::RichNative::FLAG)
      allow(Waha::EngineCapabilities).to receive(:actions).and_return(['edit'])
      react(message, '👍')
      expect(response).to have_http_status(:forbidden)
      expect(events).to be_empty
    end
  end

  describe 'edit' do
    it 'replaces the text, keeps the previous one and sends the WhatsApp text to the connector' do
      message = ours('**Até** amanhã')

      edit(message, '**Até** depois')

      expect(response).to have_http_status(:ok)
      message.reload
      expect(message.content).to eq('**Até** depois')
      expect(message.content_attributes['edit_history'].sole).to include('content' => '**Até** amanhã', 'user_id' => agent.id)
      expect(message.content_attributes['edited_at']).to be_present
      expect(events.last).to include(event: 'c2y_message_edit', id: message.id,
                                     c2y_edit: { waha_text: Waha::RichNative::OutgoingHints.whatsapp_text('**Até** depois') })
    end

    it 'refuses after the window, messages from the customer, attachments-free rule breakers and blank text' do
      old = travel_to(15.minutes.ago) { ours }
      customer = create(:message, message_type: :incoming, content: 'oi', conversation: conversation, inbox: channel.inbox,
                                  account: account)
      rich = ours('Qual?', content_attributes: { rich_message: { type: 'options', options: [{ id: 'a', title: 'A' }] } })

      [[old, 'novo'], [customer, 'novo'], [rich, 'novo'], [ours, '  ']].each do |message, content|
        edit(message, content)
        expect(response).to have_http_status(:unprocessable_entity), message.content
      end
      expect(events.select { |event| event[:event] == 'c2y_message_edit' }).to be_empty
    end

    it 'is forbidden without the engine action' do
      allow(Waha::EngineCapabilities).to receive(:actions).and_return(['react'])
      edit(ours, 'novo')
      expect(response).to have_http_status(:forbidden)
    end
  end

  it 'exposes the actions in the conversation only with the flag' do
    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}", headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['whatsapp_api_message_actions']).to eq(%w[react edit])

    account.disable_features!(Waha::RichNative::FLAG)
    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}", headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['whatsapp_api_message_actions']).to eq([])
  end
end

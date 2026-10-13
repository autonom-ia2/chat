require 'rails_helper'

# chat#1442 — toggle_typing_status repassa o "digitando" ao canal só quando a chamada traz deliver_to_channel.
RSpec.describe 'Conversation typing delivered to the channel', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:meta_typing_url) { 'https://graph.facebook.com/v22.0/123456789/messages' }
  let(:job) { Conversations::ChannelTyping::DeliverJob }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
    create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, source_id: 'wamid.LAST')
    stub_request(:post, meta_typing_url).to_return(status: 200, body: '{}')
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
  end

  def toggle(headers:, **params)
    post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/toggle_typing_status",
         headers: headers, params: { typing_status: 'on', is_private: false, **params }, as: :json
  end

  def expect_panel_event(user)
    expect(Rails.configuration.dispatcher).to have_received(:dispatch).once.with(
      Conversation::CONVERSATION_TYPING_ON, kind_of(Time), { conversation: conversation, user: user, is_private: false }
    )
  end

  context 'with deliver_to_channel' do
    it 'reaches Meta with an AgentBot token and keeps the panel event' do
      perform_enqueued_jobs(only: job) { toggle(headers: { api_access_token: agent_bot.access_token.token }, deliver_to_channel: true) }

      expect(response).to have_http_status(:ok)
      expect(response.body).to be_empty
      expect_panel_event(agent_bot)
      expect(WebMock).to have_requested(:post, meta_typing_url).once.with(body: hash_including('message_id' => 'wamid.LAST'))
    end

    it 'reaches Meta with a user token and keeps the panel event' do
      perform_enqueued_jobs(only: job) { toggle(headers: { api_access_token: agent.access_token.token }, deliver_to_channel: true) }

      expect(response).to have_http_status(:ok)
      expect_panel_event(agent)
      expect(WebMock).to have_requested(:post, meta_typing_url).once
    end

    it 'does not call the channel inside the request' do
      toggle(headers: { api_access_token: agent_bot.access_token.token }, deliver_to_channel: true)

      expect(job).to have_been_enqueued.with(conversation, 'on', kind_of(Time)).on_queue('medium')
      expect(WebMock).not_to have_requested(:post, meta_typing_url)
    end

    it 'answers success and enqueues nothing when typing_status is not on or off' do
      [{ nested: 'on' }, ['on'], 'maybe', nil].each do |typing_status|
        toggle(headers: { api_access_token: agent_bot.access_token.token }, deliver_to_channel: true, typing_status: typing_status)

        expect(response).to have_http_status(:ok)
      end

      expect(job).not_to have_been_enqueued
    end

    it 'answers success and logs when the queue is down' do
      allow(job).to receive(:perform_later).and_raise(Redis::CannotConnectError)
      allow(Rails.logger).to receive(:warn)

      toggle(headers: { api_access_token: agent_bot.access_token.token }, deliver_to_channel: true)

      expect(response).to have_http_status(:ok)
      expect(Rails.logger).to have_received(:warn).with("[channel_typing] enqueue failed conversation=#{conversation.id} Redis::CannotConnectError")
    end

    it 'answers success and logs when the check before enqueueing raises' do
      allow(Conversations::ChannelTyping::Deliverer).to receive(:supports?).and_raise(ActiveRecord::ConnectionNotEstablished)
      allow(Rails.logger).to receive(:warn)

      toggle(headers: { api_access_token: agent_bot.access_token.token }, deliver_to_channel: true)

      expect(response).to have_http_status(:ok)
      expect(Rails.logger).to have_received(:warn)
        .with("[channel_typing] enqueue failed conversation=#{conversation.id} ActiveRecord::ConnectionNotEstablished")
      expect(job).not_to have_been_enqueued
    end

    it 'enqueues nothing for an AgentBot of another inbox of the account' do
      other_bot = create(:agent_bot, account: account)
      create(:agent_bot_inbox, inbox: create(:inbox, account: account), agent_bot: other_bot)

      toggle(headers: { api_access_token: other_bot.access_token.token }, deliver_to_channel: true)

      expect(response).to have_http_status(:ok)
      expect_panel_event(other_bot)
      expect(job).not_to have_been_enqueued
    end

    it 'enqueues nothing for a private note' do
      toggle(headers: { api_access_token: agent_bot.access_token.token }, deliver_to_channel: true, is_private: true)

      expect(response).to have_http_status(:ok)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).once.with(
        Conversation::CONVERSATION_TYPING_ON, kind_of(Time), { conversation: conversation, user: agent_bot, is_private: true }
      )
      expect(job).not_to have_been_enqueued
    end

    context 'when the conversation is on Instagram' do
      let(:channel) { create(:channel_instagram, account: account) }
      let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: 'ig-contact-1') }
      let(:instagram_url) { "https://graph.instagram.com/v22.0/#{channel.instagram_id}/messages" }

      before { stub_request(:post, instagram_url).with(query: { access_token: channel.access_token }).to_return(status: 200, body: '{}') }

      it 'reaches Instagram with typing_on and typing_off' do
        perform_enqueued_jobs(only: job) do
          toggle(headers: { api_access_token: agent_bot.access_token.token }, deliver_to_channel: true)
          toggle(headers: { api_access_token: agent_bot.access_token.token }, deliver_to_channel: true, typing_status: 'off')
        end

        expect(response).to have_http_status(:ok)
        %w[typing_on typing_off].each do |sender_action|
          expect(WebMock).to have_requested(:post, instagram_url).once.with(
            query: { access_token: channel.access_token },
            body: { recipient: { id: 'ig-contact-1' }, sender_action: sender_action }
          )
        end
      end
    end

    it 'still answers success when the channel refuses' do
      stub_request(:post, meta_typing_url).to_return(status: 401, body: '{"error":{}}')

      perform_enqueued_jobs(only: job) { toggle(headers: { api_access_token: agent_bot.access_token.token }, deliver_to_channel: true) }

      expect(response).to have_http_status(:ok)
      expect(WebMock).to have_requested(:post, meta_typing_url).once
    end

    it 'still answers success when the network fails' do
      stub_request(:post, meta_typing_url).to_timeout

      perform_enqueued_jobs(only: job) { toggle(headers: { api_access_token: agent_bot.access_token.token }, deliver_to_channel: true) }

      expect(response).to have_http_status(:ok)
    end

    context 'when the channel has no typing delivery' do
      let(:channel) { create(:channel_whatsapp, account: account, provider: 'default', validate_provider_config: false, sync_templates: false) }

      it 'enqueues nothing and keeps the panel event' do
        toggle(headers: { api_access_token: agent_bot.access_token.token }, deliver_to_channel: true)

        expect(response).to have_http_status(:ok)
        expect_panel_event(agent_bot)
        expect(job).not_to have_been_enqueued
      end
    end

    it 'enqueues nothing when the installation turned channel typing off' do
      with_modified_env AI_HUMANIZE_CHANNEL_TYPING: 'false' do
        toggle(headers: { api_access_token: agent_bot.access_token.token }, deliver_to_channel: true)
      end

      expect(response).to have_http_status(:ok)
      expect_panel_event(agent_bot)
      expect(job).not_to have_been_enqueued
    end
  end

  context 'without deliver_to_channel' do
    it 'behaves as before for a user typing in the panel' do
      toggle(headers: agent.create_new_auth_token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to be_empty
      expect_panel_event(agent)
      expect(job).not_to have_been_enqueued
      expect(WebMock).not_to have_requested(:post, meta_typing_url)
    end

    it 'behaves as before for an AgentBot' do
      toggle(headers: { api_access_token: agent_bot.access_token.token })

      expect(response).to have_http_status(:ok)
      expect_panel_event(agent_bot)
      expect(job).not_to have_been_enqueued
    end

    it 'does not deliver when the field is false' do
      toggle(headers: { api_access_token: agent_bot.access_token.token }, deliver_to_channel: false)

      expect(response).to have_http_status(:ok)
      expect(job).not_to have_been_enqueued
    end
  end
end

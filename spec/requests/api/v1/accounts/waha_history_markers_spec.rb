require 'rails_helper'

RSpec.describe 'Internal WAHA history markers', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :administrator) }
  let(:channel) { create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha' }) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:headers) { { 'api_access_token' => agent.access_token.token } }
  let(:messages_url) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages" }

  before { create(:inbox_member, inbox: inbox, user: agent) }

  [true, false].each do |marker|
    it "rejects an external message history marker set to #{marker} before writing" do
      post messages_url, params: { content: 'ordinary message', content_attributes: { 'waha_history_import' => marker } },
                         headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(inbox.messages.count).to eq(0)
    end

    it "rejects an external conversation history marker set to #{marker} before writing" do
      post "/api/v1/accounts/#{account.id}/conversations",
           params: { inbox_id: inbox.id, contact_id: contact.id, source_id: contact_inbox.source_id,
                     additional_attributes: { 'waha_history_only' => marker } }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(inbox.conversations.count).to eq(0)
    end
  end

  it 'retains the internal marker when deleting the content of a historical message' do
    previous = Current.waha_history_import
    historical = begin
      Current.waha_history_import = true
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                       content_attributes: { 'history_import' => true, 'waha_history_import' => true })
    ensure
      Current.waha_history_import = previous
    end

    delete "#{messages_url}/#{historical.id}", headers: headers

    expect(response).to have_http_status(:success)
    expect(historical.reload.content_attributes).to include('deleted' => true, 'waha_history_import' => true)
    expect(inbox.messages.for_reporting.count).to eq(0)
  end

  it 'allows an ordinary conversation update without dropping its internal history marker' do
    previous = Current.waha_history_import
    historical = begin
      Current.waha_history_import = true
      create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
                            additional_attributes: { 'waha_history_only' => true })
    ensure
      Current.waha_history_import = previous
    end

    patch "/api/v1/accounts/#{account.id}/conversations/#{historical.display_id}", params: { priority: 'high' }, headers: headers, as: :json

    expect(response).to have_http_status(:success)
    expect(historical.reload.additional_attributes['waha_history_only']).to be(true)
    expect(historical.priority).to eq('high')
  end

  it 'keeps ordinary API messages in reports' do
    post messages_url, params: { content: 'ordinary message', message_type: 'incoming', content_attributes: { 'custom' => true } },
                       headers: headers, as: :json

    expect(response).to have_http_status(:success)
    expect(inbox.messages.for_reporting.count).to eq(1)
  end
end

require 'rails_helper'

RSpec.describe 'WAHA outbound message identities', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) do
    create(:channel_api, account: account, additional_attributes: {
             'provider' => 'waha', 'account_token_owner_user_id' => agent.id, 'waha_history_import' => { 'status' => 'running' }
           })
  end
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) { create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, private: false) }
  let(:source_ids) { ['true_16505551234@c.us_TEXT', 'true_16505551234@c.us_FILE'] }
  let(:url) do
    api_v1_account_conversation_message_url(account_id: account.id, conversation_id: conversation.display_id, id: message.id)
  end

  before { create(:inbox_member, inbox: inbox, user: agent) }

  it 'links every WhatsApp part to the original panel message without creating another message' do
    patch url, params: { waha_source_ids: source_ids, status: 'delivered' }, headers: { 'api_access_token' => agent.access_token.token }, as: :json

    expect(response).to have_http_status(:success)
    expect(message.reload).to have_attributes(source_id: source_ids.first, status: 'delivered')
    expect(message.additional_attributes['waha_source_ids']).to eq(source_ids)
    expect(inbox.messages.outgoing.count).to eq(1)
  end

  it 'accepts the SDK multipart array field without changing ordinary status updates' do
    patch url, params: 'waha_source_ids[]=true_16505551234%40c.us_TEXT&waha_source_ids[]=true_16505551234%40c.us_FILE',
               headers: { 'api_access_token' => agent.access_token.token }.merge('CONTENT_TYPE' => 'application/x-www-form-urlencoded')

    expect(response).to have_http_status(:success)
    expect(message.reload.additional_attributes['waha_source_ids']).to eq(source_ids)
  end

  it 'rejects malformed IDs with 422 before changing the message' do
    patch url, params: { waha_source_ids: [123] }, headers: { 'api_access_token' => agent.access_token.token }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(message.reload.source_id).to be_nil
    expect(message.additional_attributes).not_to have_key('waha_source_ids')
  end

  it 'fails closed when the existing message identity differs' do
    message.update!(source_id: 'true_16505551234@c.us_EXISTING')
    patch url, params: { waha_source_ids: source_ids }, headers: { 'api_access_token' => agent.access_token.token }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(message.reload.source_id).to eq('true_16505551234@c.us_EXISTING')
  end

  it 'rejects browser credentials even for the connector token owner' do
    patch url, params: { waha_source_ids: source_ids }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:forbidden)
    expect(message.reload.source_id).to be_nil
  end

  it 'rejects another inbox agent API token before writing identities' do
    another_agent = create(:user, account: account, role: :agent)
    create(:inbox_member, inbox: inbox, user: another_agent)
    patch url, params: { waha_source_ids: source_ids }, headers: { 'api_access_token' => another_agent.access_token.token }, as: :json

    expect(response).to have_http_status(:forbidden)
    expect(message.reload.source_id).to be_nil
  end

  it 'keeps legacy inbox status updates compatible without linking source identities' do
    channel.update!(additional_attributes: { 'provider' => 'waha' })
    patch url, params: { waha_source_ids: source_ids, status: 'delivered' }, headers: { 'api_access_token' => agent.access_token.token }, as: :json

    expect(response).to have_http_status(:success)
    expect(message.reload).to have_attributes(source_id: nil, status: 'delivered')
  end
end

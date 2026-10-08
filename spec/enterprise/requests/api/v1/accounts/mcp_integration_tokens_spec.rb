require 'rails_helper'

RSpec.describe 'MCP integration-token access', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:integration) do
    Mcp::IntegrationToken.create!(
      account: account,
      created_by: admin,
      identity_subject: 'auth-user-123',
      name: 'Autonom.ia Connect',
      scopes: Mcp::IntegrationToken::DEFAULT_SCOPES
    )
  end
  let(:headers) { { api_access_token: integration.access_token.token } }
  let(:conversation) { create(:conversation, account: account) }

  before do
    Autonomia::UserLink.create!(identity_user_id: 'auth-user-123', user: admin, email: admin.email)
  end

  it 'blocks reads and writes after the authorizing administrator is demoted' do
    token_headers = headers
    admin.account_users.find_by!(account: account).update!(role: :agent)

    get "/api/v1/accounts/#{account.id}/conversations", headers: token_headers
    expect(response).to have_http_status(:unauthorized)

    post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages",
         params: { content: 'Must not send' },
         headers: token_headers.merge('Idempotency-Key' => 'demoted-admin-123'), as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(conversation.messages.where(content: 'Must not send')).to be_empty
  end

  it 'blocks access after the human membership is removed, without waiting for the cleanup job' do
    token_headers = headers
    admin.account_users.find_by!(account: account).destroy!

    get "/api/v1/accounts/#{account.id}/contacts", headers: token_headers

    expect(response).to have_http_status(:unauthorized)
    expect(integration.reload.account_user).to be_present
  end

  it 'blocks access when the identity link is removed or reassigned to another administrator' do
    token_headers = headers
    link = Autonomia::UserLink.find_by!(identity_user_id: integration.identity_subject)
    link.update!(user: create(:user, account: account, role: :administrator))

    get "/api/v1/accounts/#{account.id}/conversations", headers: token_headers
    expect(response).to have_http_status(:unauthorized)

    link.destroy!
    get "/api/v1/accounts/#{account.id}/conversations", headers: token_headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'allows only the explicitly mapped read endpoints' do
    get "/api/v1/accounts/#{account.id}/conversations", headers: headers
    expect(response).to have_http_status(:ok)

    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages", headers: headers
    expect(response).to have_http_status(:ok)

    get "/api/v1/accounts/#{account.id}/contacts", headers: headers
    expect(response).to have_http_status(:ok)

    get "/api/v1/accounts/#{account.id}/inboxes", headers: headers
    expect(response).to have_http_status(:ok)

    delete "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}", headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'never crosses the token account boundary' do
    other_account = create(:account)

    get "/api/v1/accounts/#{other_account.id}/conversations", headers: headers

    expect(response).to have_http_status(:unauthorized)
  end

  it 'requires and honors an idempotency key when sending a message' do
    path = "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages"
    message_headers = headers.merge('Idempotency-Key' => 'agents-message-12345678')

    post path, params: { content: 'Olá', private: false }, headers: message_headers, as: :json
    expect(response).to have_http_status(:ok)

    post path, params: { content: 'Olá', private: false }, headers: message_headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.headers['Idempotency-Replayed']).to eq('true')
    expect(conversation.messages.where(content: 'Olá').count).to eq(1)
    expect(IdempotencyKey.last.key).to start_with("mcp:#{integration.id}:")
  end

  it 'denies message sending without the write scope or idempotency key' do
    read_only_account = create(:account)
    read_only_admin = create(:user, account: read_only_account, role: :administrator)
    Autonomia::UserLink.create!(identity_user_id: 'auth-user-read-only', user: read_only_admin, email: read_only_admin.email)
    read_only = Mcp::IntegrationToken.create!(
      account: read_only_account,
      created_by: read_only_admin,
      identity_subject: 'auth-user-read-only',
      name: 'Read only',
      scopes: ['agents:messages:read']
    )
    read_conversation = create(:conversation, account: read_only.account)
    path = "/api/v1/accounts/#{read_only.account_id}/conversations/#{read_conversation.display_id}/messages"

    post path,
         params: { content: 'Não enviar' },
         headers: { 'api_access_token' => read_only.access_token.token, 'Idempotency-Key' => 'agents-message-87654321' },
         as: :json
    expect(response).to have_http_status(:unauthorized)

    post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages",
         params: { content: 'Sem chave' }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'rolls back the message and claim if persisting the idempotent response fails, then permits a safe retry' do
    path = "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages"
    message_headers = headers.merge('Idempotency-Key' => 'response-failure-123')
    allow_any_instance_of(IdempotencyKey).to receive(:update!).and_raise(ActiveRecord::StatementInvalid, 'Injected persistence failure')

    post path, params: { content: 'Atomic send', private: false }, headers: message_headers, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(conversation.messages.where(content: 'Atomic send')).to be_empty
    expect(IdempotencyKey.where(account: account)).to be_empty

    allow_any_instance_of(IdempotencyKey).to receive(:update!).and_call_original
    post path, params: { content: 'Atomic send', private: false }, headers: message_headers, as: :json
    expect(response).to have_http_status(:ok)
    message_id = response.parsed_body.fetch('id')

    post path, params: { content: 'Atomic send', private: false }, headers: message_headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('id')).to eq(message_id)
    expect(response.headers['Idempotency-Replayed']).to eq('true')
    expect(conversation.messages.where(content: 'Atomic send').count).to eq(1)
  end

  it 'rolls back the message and claim if rendering fails after the message is saved' do
    path = "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages"
    message_headers = headers.merge('Idempotency-Key' => 'render-failure-123')
    allow_any_instance_of(Api::V1::Accounts::Conversations::MessagesController).to receive(:render).and_call_original
    allow_any_instance_of(Api::V1::Accounts::Conversations::MessagesController).to receive(:render)
      .with(:create).and_raise(StandardError, 'Injected render failure')

    post path, params: { content: 'Render rollback' }, headers: message_headers, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(conversation.messages.where(content: 'Render rollback')).to be_empty
    expect(IdempotencyKey.where(account: account)).to be_empty
  end

  it 'rejects reuse of a successful key for a different message' do
    path = "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages"
    message_headers = headers.merge('Idempotency-Key' => 'different-payload-123')

    post path, params: { content: 'Original message' }, headers: message_headers, as: :json
    expect(response).to have_http_status(:ok)

    post path, params: { content: 'Different message' }, headers: message_headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(conversation.messages.where(content: 'Different message')).to be_empty
  end
end

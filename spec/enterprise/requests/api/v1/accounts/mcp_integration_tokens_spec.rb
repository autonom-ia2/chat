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
         headers: { api_access_token: read_only.access_token.token, 'Idempotency-Key' => 'agents-message-87654321' },
         as: :json
    expect(response).to have_http_status(:unauthorized)

    post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages",
         params: { content: 'Sem chave' }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end
end

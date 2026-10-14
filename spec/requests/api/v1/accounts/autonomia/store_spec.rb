# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Autonomia store validation API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:super_admin) { create(:super_admin) }
  let(:client) { instance_double(Autonomia::Financial::StorePublicationClient) }
  let(:principal) { Autonomia::Agents::Agent.create!(account: account, name: 'Principal', agent_type: 'custom') }
  let(:service_id) { '20000000-0000-4000-8000-000000000001' }
  let(:base_path) { "/api/v1/accounts/#{account.id}/autonomia/financial/store" }

  before do
    create(:account_user, account: account, user: super_admin, role: :administrator)
    allow(Autonomia::Sso::TokenStore).to receive(:authorization_token_for).and_return('access-example')
    allow(Autonomia::Financial::StoreIdentity).to receive(:subject!).and_return('cognito-example-sub')
    configuration = instance_double(Autonomia::Financial::StoreConfiguration, namespace: {
                                      'installationId' => 'chat2you-test', 'productCatalogItemId' => service_id
                                    })
    allow(Autonomia::Financial::StoreConfiguration).to receive(:new).and_return(configuration)
    allow(Autonomia::Financial::StorePublicationClient).to receive(:new).and_return(client)
  end

  it 'rejects an account administrator before reading Auth or Financial' do
    get "#{base_path}/catalog", headers: auth_headers(admin)
    expect(response).to have_http_status(:forbidden)
    expect(Autonomia::Sso::TokenStore).not_to have_received(:authorization_token_for)
    expect(Autonomia::Financial::StorePublicationClient).not_to have_received(:new)
  end

  it 'allows the platform superadmin and uses the canonical Identity subject' do
    allow(client).to receive(:catalog!).with(page: 1, page_size: 20).and_return({ 'data' => [] })
    get "#{base_path}/catalog", headers: auth_headers(super_admin)
    expect(response).to have_http_status(:ok)
    expect(Autonomia::Financial::StoreIdentity).to have_received(:subject!).with('access-example')
  end

  it 'rejects a principal from another account before calling Financial' do
    other = Autonomia::Agents::Agent.create!(account: create(:account), name: 'Other', agent_type: 'custom')
    get "#{base_path}/agents/#{other.id}/services", headers: auth_headers(super_admin)
    expect(response).to have_http_status(:not_found)
    expect(Autonomia::Financial::StorePublicationClient).not_to have_received(:new)
  end

  it 'rejects deleted principals' do
    principal.update!(deleted_at: Time.current)
    get "#{base_path}/agents/#{principal.id}/services", headers: auth_headers(super_admin)
    expect(response).to have_http_status(:not_found)
  end

  it 'rejects system principals' do
    principal.update!(config: { 'system_key' => 'internal' })
    get "#{base_path}/agents/#{principal.id}/services", headers: auth_headers(super_admin)
    expect(response).to have_http_status(:not_found)
    expect(Autonomia::Financial::StorePublicationClient).not_to have_received(:new)
  end

  it 'exposes only the closed registry of supported features' do
    get "#{base_path}/features", headers: auth_headers(super_admin)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('data')).to eq(%w[prospecting email_campaigns whatsapp_api_campaigns])
    expect(Autonomia::Financial::StorePublicationClient).not_to have_received(:new)
  end

  it 'constructs a feature target without accepting operator or namespace from the browser' do
    allow(client).to receive(:create_service!).and_return({ 'service' => { 'id' => service_id } })
    post "#{base_path}/features/prospecting/services", headers: auth_headers(super_admin), as: :json,
                                                       params: { name: 'Lead search', idempotencyKey: 'example-draft-intent' }
    expect(response).to have_http_status(:created)
    expect(client).to have_received(:create_service!).with(hash_including('group' => 'feature', 'target' => {
                                                                            'type' => 'feature', 'featureKey' => 'prospecting'
                                                                          }))
  end

  it 'rejects an unknown feature before querying Financial' do
    get "#{base_path}/features/arbitrary/services", headers: auth_headers(super_admin)
    expect(response).to have_http_status(:forbidden)
    expect(Autonomia::Financial::StorePublicationClient).not_to have_received(:new)
  end

  it 'rejects a browser-provided target rather than signing arbitrary IDs' do
    payload = { name: 'Draft', idempotencyKey: 'example-draft-intent', target: { principalAgentId: 99 } }
    post "#{base_path}/agents/#{principal.id}/services", headers: auth_headers(super_admin), as: :json, params: payload
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Autonomia::Financial::StorePublicationClient).not_to have_received(:new)
  end

  it 'constructs the target from the principal in the selected account' do
    allow(client).to receive(:create_service!).and_return({ 'service' => { 'id' => service_id } })
    post "#{base_path}/agents/#{principal.id}/services", headers: auth_headers(super_admin), as: :json,
                                                         params: { name: 'Draft', idempotencyKey: 'example-draft-intent' }
    expect(response).to have_http_status(:created)
    target = { 'type' => 'agent', 'installationId' => 'chat2you-test', 'principalAgentId' => principal.id }
    expect(client).to have_received(:create_service!).with(hash_including('target' => target))
  end

  it 'rejects malformed pagination instead of coercing it' do
    get "#{base_path}/catalog", params: { page: '1junk' }, headers: auth_headers(super_admin)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'returns 401 when the Auth token is unavailable' do
    allow(Autonomia::Sso::TokenStore).to receive(:authorization_token_for).and_return(nil)
    get "#{base_path}/catalog", headers: auth_headers(super_admin)
    expect(response).to have_http_status(:unauthorized)
    expect(Autonomia::Financial::StorePublicationClient).not_to have_received(:new)
  end
end

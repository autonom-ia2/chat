# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Autonomia financial API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }

  def fake_jwt(payload)
    header = { alg: 'none', typ: 'JWT' }
    [
      Base64.urlsafe_encode64(header.to_json, padding: false),
      Base64.urlsafe_encode64(payload.to_json, padding: false),
      'signature'
    ].join('.')
  end

  it 'uses the TokenStore authorization token for subscription, invoices, and payments' do
    access_token = fake_jwt(token_use: 'access', sub: 'financial-user-id')
    client = instance_double(Autonomia::Financial::Client)

    allow(Autonomia::Sso::TokenStore).to receive(:authorization_token_for).and_return(access_token)
    allow(Autonomia::Financial::Client).to receive(:new).with(authorization_token: access_token).and_return(client)
    allow(client).to receive(:fetch!).and_return({ 'ok' => true })

    get "/api/v1/accounts/#{account.id}/autonomia/financial/subscription", headers: auth_headers(admin)
    get "/api/v1/accounts/#{account.id}/autonomia/financial/invoices", headers: auth_headers(admin)
    get "/api/v1/accounts/#{account.id}/autonomia/financial/payments", headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(Autonomia::Financial::Client).to have_received(:new).with(authorization_token: access_token).exactly(3).times
    expect(client).to have_received(:fetch!).with(:subscription)
    expect(client).to have_received(:fetch!).with(:invoices)
    expect(client).to have_received(:fetch!).with(:payments)
  end

  it 'returns unauthorized when the Auth authorization token is unavailable' do
    allow(Autonomia::Sso::TokenStore).to receive(:authorization_token_for).and_return(nil)

    get "/api/v1/accounts/#{account.id}/autonomia/financial/subscription", headers: auth_headers(admin)

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body['error']).to eq('Sua sessao do Auth expirou. Saia e entre novamente para acessar o financeiro.')
  end
end

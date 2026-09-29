# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Autonomia::Sso::Client do
  describe '#fetch_context!' do
    it 'scopes the Auth context by OAuth client and selected organization' do
      request = stub_request(
        :get,
        'https://auth.api-autonomia.com/me/context?client_id=chat2you'
      ).with(
        headers: {
          'Authorization' => 'Bearer identity-token',
          'X-Organization-Id' => 'customer-org'
        }
      ).to_return(
        status: 200,
        body: { activeOrganization: { id: 'customer-org' } }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

      response = nil
      with_modified_env AUTONOMIA_AUTH_CLIENT_ID: 'chat2you' do
        response = described_class.new.fetch_context!(
          'identity-token',
          organization_id: 'customer-org'
        )
      end

      expect(request).to have_been_requested.once
      expect(response.dig('activeOrganization', 'id')).to eq('customer-org')
    end
  end

  describe '#exchange_code!' do
    it 'preserves the selected organization returned by Auth' do
      stub_request(:post, 'https://auth.api-autonomia.com/oauth/token').to_return(
        status: 200,
        body: {
          access_token: 'access-token',
          organization_id: 'customer-org'
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

      token = described_class.new.exchange_code!(
        code: 'code',
        redirect_uri: 'https://chat.example.com/auth/callback',
        code_verifier: 'verifier'
      )

      expect(token.organization_id).to eq('customer-org')
    end
  end
end

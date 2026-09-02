# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Autonomia::Financial::Client do
  describe '#fetch!' do
    let(:base_url) { 'https://financial.example.test' }

    it 'sends the supplied authorization token as a bearer token' do
      token = 'identity-access-token'
      stub = stub_request(:get, "#{base_url}/financial/me/subscription")
             .with(headers: { 'Authorization' => "Bearer #{token}", 'Accept' => 'application/json' })
             .to_return(status: 200, body: { ok: true }.to_json, headers: { 'Content-Type' => 'application/json' })

      payload = with_modified_env(AUTONOMIA_FINANCIAL_API_BASE_URL: base_url) do
        described_class.new(authorization_token: token).fetch!(:subscription)
      end

      expect(stub).to have_been_requested
      expect(payload).to eq('ok' => true)
    end
  end
end

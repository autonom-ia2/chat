# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Vigia::Instrumentation do
  describe '.normalize_path' do
    it 'normalizes dynamic ids, uuids, emails, tokens and query strings' do
      path = '/api/v1/accounts/17/conversations/6/users/user@example.com/tokens/abcDEF1234567890abcDEF123456?secret=hidden'

      expect(described_class.normalize_path(path)).to eq('/api/v1/accounts/{id}/conversations/{id}/users/{value}/tokens/{token}')
    end
  end

  describe '.http_payload' do
    it 'marks 4xx responses as successful operational executions' do
      payload = described_class.http_payload(
        env: Rack::MockRequest.env_for('/missing', method: 'GET'),
        status: 404,
        started_at: Time.zone.parse('2026-08-26 12:00:00'),
        ended_at: Time.zone.parse('2026-08-26 12:00:01')
      )

      expect(payload[:outcome]).to eq('success')
      expect(payload).not_to have_key(:errorClass)
    end

    it 'marks 5xx responses as failures' do
      payload = described_class.http_payload(
        env: Rack::MockRequest.env_for('/broken', method: 'POST'),
        status: 500,
        started_at: Time.zone.parse('2026-08-26 12:00:00'),
        ended_at: Time.zone.parse('2026-08-26 12:00:01')
      )

      expect(payload[:outcome]).to eq('failure')
      expect(payload[:errorClass]).to eq('INTERNAL')
    end
  end
end

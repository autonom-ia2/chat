# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Vigia::Client do
  describe '.record_execution' do
    let(:payload) do
      {
        eventId: 'cw-test-event',
        operation: 'GET /health',
        kind: 'http_request',
        startedAt: '2026-08-26T12:00:00.000Z',
        endedAt: '2026-08-26T12:00:00.001Z',
        durationMs: 1,
        outcome: 'success',
        occurredAt: '2026-08-26T12:00:00.001Z'
      }
    end

    it 'posts execution telemetry when enabled' do
      with_modified_env(
        'VIGIA_ENABLED' => 'true',
        'VIGIA_BASE_URL' => 'https://vigia.local',
        'VIGIA_API_KEY' => 'vigia_test_secret'
      ) do
        request = stub_request(:post, 'https://vigia.local/v1/executions')
                  .with(headers: { 'Authorization' => 'Bearer vigia_test_secret' })
                  .to_return(status: 200, body: '{}')

        expect(described_class.record_execution(payload)).to be(true)
        expect(request).to have_been_requested
      end
    end

    it 'does not send telemetry when disabled' do
      with_modified_env('VIGIA_ENABLED' => 'false', 'VIGIA_API_KEY' => 'vigia_test_secret') do
        expect(described_class.record_execution(payload)).to be(false)
        expect(WebMock).not_to have_requested(:post, /vigia/)
      end
    end

    it 'fails open when Vigia cannot be reached' do
      with_modified_env(
        'VIGIA_ENABLED' => 'true',
        'VIGIA_BASE_URL' => 'https://vigia.local',
        'VIGIA_API_KEY' => 'vigia_test_secret'
      ) do
        stub_request(:post, 'https://vigia.local/v1/executions').to_raise(Faraday::TimeoutError)

        expect(described_class.record_execution(payload)).to be(false)
      end
    end
  end
end

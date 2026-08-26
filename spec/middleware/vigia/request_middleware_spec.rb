# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Vigia::RequestMiddleware do
  let(:env) do
    Rack::MockRequest.env_for(
      '/api/v1/accounts/17/conversations?token=secret',
      method: 'GET',
      'HTTP_COOKIE' => 'session=secret',
      'HTTP_AUTHORIZATION' => 'Bearer secret'
    ).merge(
      'action_dispatch.route_uri_pattern' => '/api/v1/accounts/:account_id/conversations',
      'action_dispatch.request_id' => 'request-123456'
    )
  end

  it 'records successful requests without headers, cookies, body or raw query strings' do
    recorded_payloads = []
    allow(Vigia::Client).to receive(:record_execution) { |payload| recorded_payloads << payload }
    app = ->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['ok']] }

    response = described_class.new(app).call(env)

    expect(response.first).to eq(200)
    payload = recorded_payloads.first
    expect(payload[:outcome]).to eq('success')
    expect(payload[:httpRoute]).to eq('/api/v1/accounts/:account_id/conversations')
    expect(payload.to_json).not_to include('secret')
  end

  it 'records raised exceptions and re-raises them' do
    recorded_payloads = []
    allow(Vigia::Client).to receive(:record_execution) { |payload| recorded_payloads << payload }
    app = ->(_env) { raise StandardError, 'boom' }

    expect { described_class.new(app).call(env) }.to raise_error(StandardError, 'boom')

    payload = recorded_payloads.first
    expect(payload[:outcome]).to eq('failure')
    expect(payload[:errorClass]).to eq('INTERNAL')
    expect(payload[:errorType]).to eq('StandardError')
  end
end

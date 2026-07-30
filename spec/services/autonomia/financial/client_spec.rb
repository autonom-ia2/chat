# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Autonomia::Financial::Client do
  describe '#fetch!' do
    it 'sends the supplied authorization token as a bearer token' do
      token = 'identity-access-token'
      http = instance_double(Net::HTTP)
      response = Net::HTTPOK.new('1.1', '200', 'OK')
      captured_request = nil
      response.body = { ok: true }.to_json

      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request) do |request|
        captured_request = request
        response
      end

      described_class.new(authorization_token: token).fetch!(:subscription)

      expect(captured_request['Authorization']).to eq("Bearer #{token}")
      expect(captured_request['Accept']).to eq('application/json')
    end
  end
end

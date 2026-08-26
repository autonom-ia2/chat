# frozen_string_literal: true

require 'rails_helper'

class VigiaSuccessTestJob < ApplicationJob
  queue_as :default

  def perform(_secret = nil)
    true
  end
end

class VigiaFailureTestJob < ApplicationJob
  queue_as :critical

  def perform(_secret = nil)
    raise StandardError, 'job failed'
  end
end

RSpec.describe ApplicationJob do
  it 'records job success without serialized arguments' do
    recorded_payloads = []
    allow(Vigia::Client).to receive(:record_execution) { |payload| recorded_payloads << payload }

    VigiaSuccessTestJob.perform_now('do-not-log-this')

    payload = recorded_payloads.first
    expect(payload[:operation]).to eq('job:VigiaSuccessTestJob')
    expect(payload[:kind]).to eq('job')
    expect(payload[:outcome]).to eq('success')
    expect(payload.to_json).not_to include('do-not-log-this')
  end

  it 'records job failure and preserves the original exception' do
    recorded_payloads = []
    allow(Vigia::Client).to receive(:record_execution) { |payload| recorded_payloads << payload }

    expect { VigiaFailureTestJob.perform_now('do-not-log-this') }.to raise_error(StandardError, 'job failed')

    payload = recorded_payloads.first
    expect(payload[:operation]).to eq('job:VigiaFailureTestJob')
    expect(payload[:outcome]).to eq('failure')
    expect(payload[:errorClass]).to eq('INTERNAL')
    expect(payload[:errorType]).to eq('StandardError')
    expect(payload.to_json).not_to include('do-not-log-this')
  end
end

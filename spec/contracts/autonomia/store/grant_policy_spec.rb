require_relative '../financial/store_spec_helper'
module Autonomia::Store; end
require_relative '../../../../app/services/autonomia/store/grant_policy'

RSpec.describe Autonomia::Store::GrantPolicy do
  let(:fixture) { JSON.parse(File.read(File.expand_path('../../../fixtures/autonomia_store/contracts.v1.json', __dir__))) }
  let(:snapshot) { fixture['storeEvent']['data'] }
  let(:now) { Time.iso8601('2026-10-13T12:00:00Z') }
  let(:subscription_id) { fixture['serviceSubscription']['id'] }
  let(:reservation_id) { fixture['reservationResponse']['reservation']['id'] }

  it 'accepts only the confirmed matching grant, never a pending reservation or unrelated grant' do
    expect(described_class.allowed?(snapshot, subscription_id: subscription_id, reservation_id: reservation_id, now: now)).to be(true)
    expect(described_class.allowed?(snapshot, subscription_id: subscription_id, reservation_id: 'other', now: now)).to be(false)
    snapshot['effectiveAccess'] = 'suspended'
    expect(described_class.allowed?(snapshot, subscription_id: subscription_id, reservation_id: reservation_id, now: now)).to be(false)
  end

  it 'does not accept expired grants just because another buyer has effective access' do
    snapshot['grants'][0]['effectiveUntil'] = '2026-10-12T12:00:00Z'
    expect(described_class.allowed?(snapshot, subscription_id: subscription_id, reservation_id: reservation_id, now: now)).to be(false)
  end

  it 'does not revoke the first buyer when another grant has ended' do
    snapshot['grants'][1]['status'] = 'ended'
    expect(described_class.allowed?(snapshot, subscription_id: subscription_id, reservation_id: reservation_id, now: now)).to be(true)
  end
end

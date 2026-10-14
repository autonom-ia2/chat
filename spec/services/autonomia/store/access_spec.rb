require 'rails_helper'

RSpec.describe Autonomia::Store::Access do
  let(:fixture) { JSON.parse(Rails.root.join('spec/fixtures/autonomia_store/checkout.v1.json').read) }
  let(:account) { create(:account) }
  let(:namespace) { fixture.dig('entitlementsResponse', 'namespace') }
  let(:activation) do
    Autonomia::Store::Activation.create!(
      user: create(:super_admin), account: account, installation_id: namespace.fetch('installationId'),
      product_catalog_item_id: namespace.fetch('productCatalogItemId'),
      buyer_subject: fixture.dig('checkoutResponse', 'buyer', 'cognitoSub'),
      service_subscription_id: fixture.dig('reservationResponse', 'reservation', 'serviceSubscriptionId'),
      service_catalog_item_id: fixture.dig('entitlementsResponse', 'data', 'serviceCatalogItemId'),
      feature_key: 'prospecting', resource_id: account.id.to_s, metric_key: 'feature_activations',
      operation_intent: SecureRandom.uuid, occurred_at: Time.current, state: 'ready',
      reservation_id: fixture.dig('reservationResponse', 'reservation', 'id')
    )
  end
  let(:snapshot) do
    fixture.fetch('entitlementsResponse').deep_dup.tap do |result|
      result['data']['resourceRef'] = activation.resource_ref
      result['data']['grants'].first['effectiveUntil'] = 1.day.from_now.iso8601
    end
  end

  around do |example|
    with_modified_env('FINANCIAL_STORE_INSTALLATION_ID' => namespace.fetch('installationId'),
                      'FINANCIAL_STORE_PRODUCT_CATALOG_ITEM_ID' => namespace.fetch('productCatalogItemId')) { example.run }
  end

  it 'requires both a ready activation and its matching confirmed grant' do
    activation
    expect(described_class.allowed?(account, 'prospecting')).to be(false)
    Autonomia::Store::Projection.apply!(snapshot)
    expect(described_class.allowed?(account, 'prospecting')).to be(true)
    activation.update!(state: 'disabling')
    expect(described_class.allowed?(account, 'prospecting')).to be(false)
  end

  it 'does not use a feature grant belonging to a different account' do
    Autonomia::Store::Projection.apply!(snapshot)
    expect(described_class.allowed?(create(:account), 'prospecting')).to be(false)
  end

  it 'does not grant purchased access to an inactive beneficiary account' do
    Autonomia::Store::Projection.apply!(snapshot)
    account.update!(status: :suspended)
    expect(described_class.allowed?(account, 'prospecting')).to be(false)
    expect(activation.reload.state).to eq('ready')
  end

  it 'does not use another installation namespace' do
    Autonomia::Store::Projection.apply!(snapshot)
    with_modified_env('FINANCIAL_STORE_INSTALLATION_ID' => 'other-test-installation') do
      expect(described_class.allowed?(account, 'prospecting')).to be(false)
    end
  end

  it 'keeps the newest full projection when events arrive out of order' do
    Autonomia::Store::Projection.apply!(snapshot)
    revoked = snapshot.deep_dup
    revoked['accessVersion'] = '3'
    revoked['data']['effectiveAccess'] = 'ended'
    revoked['data']['grants'].first['status'] = 'revoked'
    Autonomia::Store::Projection.apply!(revoked)
    Autonomia::Store::Projection.apply!(snapshot.merge('accessVersion' => '2'))
    expect(described_class.allowed?(account, 'prospecting')).to be(false)
    expect(Autonomia::Store::Entitlement.last.access_version.to_i).to eq(3)
  end

  it 'does not let another buyer revoked grant remove this buyer valid grant' do
    other = snapshot['data']['grants'].first.merge('serviceSubscriptionId' => SecureRandom.uuid,
                                                   'reservationId' => SecureRandom.uuid, 'status' => 'revoked')
    snapshot['data']['grants'] << other
    Autonomia::Store::Projection.apply!(snapshot)
    expect(described_class.allowed?(account, 'prospecting')).to be(true)
  end

  it 'does not replace manually granted prospecting access with a store decision' do
    account.update!(internal_attributes: { 'autonomia_prospecting_enabled' => true })
    expect(described_class).not_to receive(:allowed?)
    expect(Autonomia::Prospecting::Config.enabled?(account)).to be(true)
  end
end

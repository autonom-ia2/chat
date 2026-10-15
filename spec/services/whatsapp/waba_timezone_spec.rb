require 'rails_helper'

RSpec.describe Whatsapp::WabaTimezone do
  # A fábrica grava WABA 123456789 e token test_key em toda caixa whatsapp_cloud.
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:url) { "https://graph.facebook.com/#{Whatsapp::Templates::MetaClient.api_version}/123456789" }

  def answer(body, status: 200)
    stub_request(:get, url).with(query: { fields: 'timezone_id' }, headers: { 'Authorization' => 'Bearer test_key' })
                           .to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  before { allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new) }

  it 'turns the WABA timezone_id into the IANA zone, with the token only in the header' do
    request = answer({ 'id' => 'waba-1', 'timezone_id' => '25' })

    expect(described_class.for(channel).tzinfo.identifier).to eq('America/Sao_Paulo')
    expect(request).to have_been_requested.once
  end

  it 'asks Meta once and keeps the answer' do
    request = answer({ 'timezone_id' => '1' })

    2.times { expect(described_class.for(channel).tzinfo.identifier).to eq('America/Los_Angeles') }
    expect(request).to have_been_requested.once
  end

  it 'answers nil, logs only the reason and keeps the failure for a while when Meta refuses' do
    request = answer({ 'error' => { 'message' => 'Invalid OAuth access token test_key' } }, status: 400)
    allow(Rails.logger).to receive(:warn)

    2.times { expect(described_class.for(channel)).to be_nil }
    expect(request).to have_been_requested.once
    expect(Rails.logger).to have_received(:warn).with(/timezone_lookup_failed=http_400\z/).once
  end

  it 'answers nil for an id outside the official table' do
    answer({ 'timezone_id' => '0' })

    expect(described_class.for(channel)).to be_nil
  end

  it 'logs only the class when the request breaks' do
    stub_request(:get, url).with(query: { fields: 'timezone_id' }).to_raise(Net::OpenTimeout)
    allow(Rails.logger).to receive(:warn)

    expect(described_class.for(channel)).to be_nil
    expect(Rails.logger).to have_received(:warn).with(/timezone_lookup_failed=Net::OpenTimeout\z/)
  end

  it 'does not ask Meta without a numeric WABA' do
    channel.provider_config['business_account_id'] = '123/../me'

    expect(described_class.for(channel)).to be_nil
    channel.provider_config.delete('business_account_id')
    expect(described_class.for(channel)).to be_nil
  end

  it 'never sends a 360Dialog key to Meta' do
    channel.provider = 'default'

    expect(described_class.for(channel)).to be_nil
  end

  it 'maps every name of the official Meta table to an IANA zone, except the placeholders and zones newer than tzdata' do
    unmapped = described_class.meta_names.values.reject { |name| described_class.iana_by_meta_name[name] }

    expect(unmapped - %w[TZ_UNKNOWN TZ_NUM_TIMEZONES TZ_AMERICA_COYHAIQUE]).to be_empty
    expect(described_class.iana_for(370)).to eq('Etc/GMT+1')
  end
end

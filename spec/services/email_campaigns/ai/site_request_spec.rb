require 'rails_helper'

RSpec.describe EmailCampaigns::Ai::SiteRequest, :aggregate_failures do
  let(:account) { create(:account) }
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:credential) { { api_key: 'test-key' } }

  before { allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client) }

  def answer(site_url, reason = 'motivo')
    allow(client).to receive(:create).and_return(text: { site_url: site_url, reason: reason }.to_json)
  end

  def site_url(brief)
    described_class.new(account: account, credential: credential, brief: brief).url
  end

  it 'asks the small model, with the briefing as inert data, and returns the address it found' do
    answer('https://aurora.example/')

    expect(site_url('Use a identidade do site https://aurora.example')).to eq('https://aurora.example/')
    expect(Crm::Ai::ResponsesClient).to have_received(:new)
      .with(credential: credential, feature: 'email_site_request', account: account, max_retries: 0)
    expect(client).to have_received(:create) do |**request|
      expect(request[:model]).to eq(Crm::Ai::Config::MODEL_CLASSIFY)
      expect(request[:timeout]).to eq(described_class::TIMEOUT)
      expect(request[:schema][:schema][:properties][:site_url]).to eq(type: %w[string null])
      expect(request[:schema][:schema][:required]).to eq(%w[site_url reason])
      expect(request[:input]).to include('<<<PEDIDO', 'https://aurora.example', 'PEDIDO>>>')
    end
  end

  it 'caps the briefing it sends' do
    answer(nil)

    site_url("Promoção #{'x' * (described_class::BRIEF_MAX * 2)}")

    expect(client).to have_received(:create) do |**request|
      expect(request[:input].length).to be < described_class::BRIEF_MAX + 200
    end
  end

  it 'returns nil when the model says no site was asked for' do
    answer(nil)

    expect(site_url('Promoção de Natal, link para https://loja.example/natal')).to be_nil
  end

  it 'completes an address without scheme and refuses anything that is not http(s)' do
    answer('aurora.example')
    expect(site_url('use aurora.example')).to eq('https://aurora.example')

    %w[ftp://aurora.example/ javascript:alert(1) https://user:pass@aurora.example/ nada].each do |value|
      answer(value)
      expect(site_url('qualquer pedido')).to be_nil
    end
  end

  it 'goes on without a site when the call fails or the answer is not JSON' do
    allow(Rails.logger).to receive(:info)
    allow(client).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'network_timeout: read_timeout')
    expect(site_url('use https://aurora.example')).to be_nil

    allow(client).to receive(:create).and_return(text: 'não sei')
    expect(site_url('use https://aurora.example')).to be_nil
    expect(Rails.logger).to have_received(:info).with(include('[EmailCampaigns::Ai::SiteRequest]')).twice
  end

  it 'does not call the model without a briefing or with BRAND_KITS_ENABLED off' do
    allow(client).to receive(:create)

    expect(site_url('   ')).to be_nil
    with_modified_env(BRAND_KITS_ENABLED: 'false') { expect(site_url('use https://aurora.example')).to be_nil }
    expect(client).not_to have_received(:create)
  end
end

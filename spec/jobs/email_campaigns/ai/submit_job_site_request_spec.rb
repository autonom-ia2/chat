require 'rails_helper'

# #1111: an address in the request ("use a identidade do site https://...") is read like "Usar outro site".
# The small model decides whether a site was asked for; the provider is always fake here.
RSpec.describe EmailCampaigns::Ai::SubmitJob, :aggregate_failures do
  let(:account) { create(:account) }
  let(:campaign) { create(:email_campaign, account: account) }
  let(:kit) { create(:brand_kit, account: account, name: 'Hub2You', is_default: true) }
  let(:client) { instance_double(Crm::Ai::ResponsesClient, create_background: { id: 'resp_1', status: 'queued' }) }
  let(:proposal) do
    { 'name' => 'Aurora', 'source_url' => 'https://aurora.example/',
      'appearance' => kit.appearance.deep_merge('palettes' => { 'light' => { 'primary' => '#0055aa' } }, 'logo_url' => nil) }
  end
  let(:brand) { { 'kit_id' => kit.id, 'mode' => 'light' } }

  around { |example| with_modified_env(FRONTEND_URL: 'https://app.example.com') { example.run } }

  before do
    resolver = instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'test-key' })
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    allow(BrandKits::SiteImporter).to receive(:new).and_return(instance_double(BrandKits::SiteImporter, perform: proposal))
  end

  def interpretation(site_url)
    allow(client).to receive(:create).and_return(text: { site_url: site_url, reason: 'motivo' }.to_json)
  end

  def generate(brief, extra = {})
    token = campaign.ai_begin!
    described_class.perform_now(campaign.id, token, { 'brief' => brief, 'placeholders' => [], 'assets' => [], 'brand' => brand }.merge(extra))
    token
  end

  it 'reads the site asked for and writes its palette into the prompt instead of the default identity' do
    interpretation('https://aurora.example/')

    token = generate('Promoção de primavera. Use a identidade do site https://aurora.example')

    expect(BrandKits::SiteImporter).to have_received(:new).with('https://aurora.example/')
    expect(client).to have_received(:create_background) do |**request|
      expect(request[:instructions]).to include('"name":"Aurora"', 'PRIMARY=#0055aa', 'aurora.example')
      expect(request[:instructions]).not_to include('PRIMARY=#c8102e')
    end
    import = BrandImportJob.find_by!(account: account)
    expect(EmailCampaigns::Ai::PollJob).to have_been_enqueued.with(
      campaign.id, token, 'resp_1', 0,
      { 'brand_identity' => { 'name' => 'Aurora', 'mode' => 'light', 'source' => 'site', 'source_url' => 'https://aurora.example/',
                              'site_request' => { 'host' => 'aurora.example', 'status' => 'used', 'import_id' => import.id } },
        'placeholders' => [] }
    )
  end

  it 'does not read any site when the model finds none' do
    interpretation(nil)

    generate('Promoção de primavera com link para https://loja.example/primavera')

    expect(BrandKits::SiteImporter).not_to have_received(:new)
    expect(client).to have_received(:create_background) do |**request|
      expect(request[:instructions]).to include('"name":"Hub2You"', 'PRIMARY=#c8102e')
    end
  end

  it 'still generates when the interpretation call fails' do
    allow(client).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'network_timeout: read_timeout')

    token = generate('Use a identidade do site https://aurora.example')

    expect(BrandKits::SiteImporter).not_to have_received(:new)
    expect(client).to have_received(:create_background)
    expect(campaign.reload.ai_generation_token).to eq(token)
    expect(campaign.ai_status).to eq('processing')
  end

  it 'keeps the default identity and records a notice when the site cannot be read' do
    interpretation('https://aurora.example/')
    allow(BrandKits::SiteImporter).to receive(:new).and_raise(BrandKits::SiteImporter::Error.new('timeout'))

    token = generate('Use a identidade do site https://aurora.example')

    expect(client).to have_received(:create_background) do |**request|
      expect(request[:instructions]).to include('"name":"Hub2You"', 'PRIMARY=#c8102e')
    end
    expect(EmailCampaigns::Ai::PollJob).to have_been_enqueued.with(
      campaign.id, token, 'resp_1', 0,
      { 'brand_identity' => { 'kit_id' => kit.id, 'name' => 'Hub2You', 'mode' => 'light', 'source' => 'kit',
                              'site_request' => { 'host' => 'aurora.example', 'status' => 'unreadable' } },
        'placeholders' => [] }
    )
  end

  it 'restyles the e-mail on the screen with the site in "Ajustar com IA" and tells the editor' do
    interpretation('https://aurora.example/')
    base = "<mjml><mj-body>#{EmailAdjustFixture::HERO}#{EmailCampaigns::LockedFooter::MJML}</mj-body></mjml>"

    token = generate('Use a identidade do site https://aurora.example', 'base_mjml' => base)

    expect(client).to have_received(:create_background) do |**request|
      expect(request[:schema]).to eq(EmailCampaigns::Ai::EditPromptBuilder::SCHEMA)
      expect(request[:instructions]).to include('"name":"Aurora"', 'PRIMARY=#0055aa', 'aurora.example')
    end
    adjustment = EmailCampaigns::Ai::Adjustment.find(campaign, token)
    expect(adjustment['site_request']).to include('host' => 'aurora.example', 'status' => 'used')
    EmailCampaigns::Ai::Adjustment.update(campaign, token, status: 'proposed', mjml: base, summary: 'Troquei as cores.')
    expect(EmailCampaigns::Ai::Adjustment.presented(campaign, token)['site_request']).to include('host' => 'aurora.example')
  end
end

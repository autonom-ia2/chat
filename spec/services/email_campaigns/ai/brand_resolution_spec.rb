require 'rails_helper'

RSpec.describe EmailCampaigns::Ai::BrandResolution, :aggregate_failures do
  let(:account) { create(:account) }
  let(:campaign) { create(:email_campaign, account: account) }
  let(:kit) { create(:brand_kit, account: account, name: 'Hub2You') }

  around { |example| with_modified_env(FRONTEND_URL: 'https://app.example.com') { example.run } }

  it 'resolves a kit of the account into the prompt identity and the snapshot the campaign records' do
    identity, snapshot = described_class.new(campaign, { 'kit_id' => kit.id, 'mode' => 'dark' }).call

    expect(identity).to include(name: 'Hub2You', mode: 'dark')
    expect(identity[:palette]).to include(background: '#0b243f')
    expect(snapshot).to eq('kit_id' => kit.id, 'name' => 'Hub2You', 'mode' => 'dark', 'source' => 'kit')
  end

  it 'ignores a kit of another account' do
    expect(described_class.new(campaign, { 'kit_id' => create(:brand_kit).id }).call).to eq([nil, {}])
  end

  it 'stores the logo of a site read for this e-mail with the campaign and never points at the site for it' do
    proposal = { 'name' => 'Aurora', 'appearance' => kit.appearance.merge('logo_url' => 'https://aurora.example/logo.png') }
    import = create(:brand_import_job, account: account, url: 'https://aurora.example/', status: :succeeded, result: proposal)
    blob = ActiveStorage::Blob.create_and_upload!(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'logo.png')
    allow(BrandKits::LogoDownloader).to receive(:blob_from).with('https://aurora.example/logo.png').and_return(blob)

    identity, snapshot = described_class.new(campaign, { 'import_id' => import.id }).call

    expect(identity[:logo_url]).to start_with('https://app.example.com/rails/active_storage/blobs/')
    expect(campaign.reload.builder_assets.blobs).to include(blob)
    expect(snapshot).to eq('name' => 'Aurora', 'mode' => 'light', 'source' => 'site', 'source_url' => 'https://aurora.example/')
  end

  it 'goes without logo when the logo of the site cannot be stored' do
    proposal = { 'name' => 'Aurora', 'appearance' => kit.appearance.merge('logo_url' => 'https://aurora.example/logo.svg') }
    import = create(:brand_import_job, account: account, status: :succeeded, result: proposal)
    allow(BrandKits::LogoDownloader).to receive(:blob_from).and_raise(BrandKits::LogoDownloader::Error.new('logo_unsupported_type'))

    identity, = described_class.new(campaign, { 'import_id' => import.id }).call

    expect(identity[:logo_url]).to be_nil
  end

  context 'with a site the person asked for in the request (#1111)' do
    let(:site_appearance) do
      kit.appearance.deep_merge('palettes' => { 'light' => { 'primary' => '#0055aa' } }, 'logo_url' => 'https://aurora.example/logo.png')
    end
    let(:proposal) { { 'name' => 'Aurora', 'source_url' => 'https://aurora.example/', 'appearance' => site_appearance } }
    let(:blob) { ActiveStorage::Blob.create_and_upload!(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'logo.png') }

    before { allow(BrandKits::LogoDownloader).to receive(:blob_from).and_return(blob) }

    it 'reads the site, uses it instead of the chosen kit for this e-mail and keeps the reading to save later' do
      importer = instance_double(BrandKits::SiteImporter, perform: proposal)
      allow(BrandKits::SiteImporter).to receive(:new).with('https://aurora.example/').and_return(importer)

      identity, snapshot = described_class.new(campaign, { 'kit_id' => kit.id }, requested_url: 'https://aurora.example/').call

      import = BrandImportJob.find_by!(account: account, url: 'https://aurora.example/')
      expect(import).to be_succeeded
      expect(import.result['name']).to eq('Aurora')
      expect(identity).to include(name: 'Aurora', requested_site: 'aurora.example')
      expect(identity[:palette]).to include(primary: '#0055aa')
      expect(identity[:logo_url]).to start_with('https://app.example.com/rails/active_storage/blobs/')
      expect(BrandKits::LogoDownloader).to have_received(:blob_from).with('https://aurora.example/logo.png')
      expect(snapshot).to eq('name' => 'Aurora', 'mode' => 'light', 'source' => 'site', 'source_url' => 'https://aurora.example/',
                             'site_request' => { 'host' => 'aurora.example', 'status' => 'used', 'import_id' => import.id })
    end

    it 'refuses a private address and keeps the chosen identity, with a notice' do
      identity, snapshot = described_class.new(campaign, { 'kit_id' => kit.id }, requested_url: 'http://127.0.0.1/').call

      expect(identity).to include(name: 'Hub2You')
      expect(identity).not_to have_key(:requested_site)
      expect(snapshot).to eq('kit_id' => kit.id, 'name' => 'Hub2You', 'mode' => 'light', 'source' => 'kit',
                             'site_request' => { 'host' => '127.0.0.1', 'status' => 'unreadable' })
      expect(BrandImportJob.where(account: account).pluck(:status, :error_code)).to eq([%w[failed unsafe_url]])
    end

    it 'marks every read as coming from the request, failed ones too' do
      allow(BrandKits::SiteImporter).to receive(:new).and_return(instance_double(BrandKits::SiteImporter, perform: proposal))
      described_class.new(campaign, nil, requested_url: 'https://aurora.example/').call
      allow(BrandKits::SiteImporter).to receive(:new).and_raise(BrandKits::SiteImporter::Error.new('timeout'))
      described_class.new(campaign, nil, requested_url: 'https://aurora.example/').call

      reads = BrandImportJob.where(account: account).order(:id)
      expect(reads.map(&:status)).to eq(%w[succeeded failed])
      expect(reads.map { |read| read.result['origin'] }).to eq([BrandImportJob::ORIGIN_BRIEFING] * 2)
      expect(reads.last.error_code).to eq('timeout')
      expect(BrandImportJob.where(account: account).from_briefing.count).to eq(2)
      expect(BrandImportJob.where(account: account).from_import_screen.count).to eq(0)
    end

    it 'stops reading sites from requests after the hourly cap of the account' do
      create_list(:brand_import_job, BrandImportJob::BRIEFING_HOURLY_LIMIT, account: account, status: :failed,
                                                                            result: { 'origin' => BrandImportJob::ORIGIN_BRIEFING })
      allow(BrandKits::SiteImporter).to receive(:new)

      identity, snapshot = described_class.new(campaign, { 'kit_id' => kit.id }, requested_url: 'https://aurora.example/').call

      expect(BrandKits::SiteImporter).not_to have_received(:new)
      expect(identity).to include(name: 'Hub2You')
      expect(snapshot['site_request']).to eq('host' => 'aurora.example', 'status' => 'unreadable')
    end

    it 'says so when the site cannot be read and there is no identity to fall back on' do
      allow(BrandKits::SiteImporter).to receive(:new).and_raise(BrandKits::SiteImporter::Error.new('http_error'))

      expect(described_class.new(campaign, nil, requested_url: 'https://aurora.example/').call)
        .to eq([nil, { 'site_request' => { 'host' => 'aurora.example', 'status' => 'unreadable' } }])
    end
  end

  it 'gives no identity when BRAND_KITS_ENABLED is off' do
    with_modified_env(BRAND_KITS_ENABLED: 'false') do
      expect(described_class.new(campaign, { 'kit_id' => kit.id }).call).to eq([nil, {}])
    end
  end
end

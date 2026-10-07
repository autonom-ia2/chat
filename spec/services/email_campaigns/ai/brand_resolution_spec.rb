require 'rails_helper'

RSpec.describe EmailCampaigns::Ai::BrandResolution, :aggregate_failures do
  let(:account) { create(:account) }
  let(:campaign) { create(:email_campaign, account: account) }
  let(:kit) { create(:brand_kit, account: account, name: 'Hub2You') }

  around { |example| with_modified_env(FRONTEND_URL: 'https://app.example.com') { example.run } }

  it 'resolves a kit of the account into the prompt identity and the snapshot the campaign records' do
    identity, snapshot = described_class.new(campaign, 'kit_id' => kit.id, 'mode' => 'dark').call

    expect(identity).to include(name: 'Hub2You', mode: 'dark')
    expect(identity[:palette]).to include(background: '#0b243f')
    expect(snapshot).to eq('kit_id' => kit.id, 'name' => 'Hub2You', 'mode' => 'dark', 'source' => 'kit')
  end

  it 'ignores a kit of another account' do
    expect(described_class.new(campaign, 'kit_id' => create(:brand_kit).id).call).to eq([nil, {}])
  end

  it 'stores the logo of a site read for this e-mail with the campaign and never points at the site for it' do
    proposal = { 'name' => 'Aurora', 'appearance' => kit.appearance.merge('logo_url' => 'https://aurora.example/logo.png') }
    import = create(:brand_import_job, account: account, url: 'https://aurora.example/', status: :succeeded, result: proposal)
    blob = ActiveStorage::Blob.create_and_upload!(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'logo.png')
    allow(BrandKits::LogoDownloader).to receive(:blob_from).with('https://aurora.example/logo.png').and_return(blob)

    identity, snapshot = described_class.new(campaign, 'import_id' => import.id).call

    expect(identity[:logo_url]).to start_with('https://app.example.com/rails/active_storage/blobs/')
    expect(campaign.reload.builder_assets.blobs).to include(blob)
    expect(snapshot).to eq('name' => 'Aurora', 'mode' => 'light', 'source' => 'site', 'source_url' => 'https://aurora.example/')
  end

  it 'goes without logo when the logo of the site cannot be stored' do
    proposal = { 'name' => 'Aurora', 'appearance' => kit.appearance.merge('logo_url' => 'https://aurora.example/logo.svg') }
    import = create(:brand_import_job, account: account, status: :succeeded, result: proposal)
    allow(BrandKits::LogoDownloader).to receive(:blob_from).and_raise(BrandKits::LogoDownloader::Error.new('logo_unsupported_type'))

    identity, = described_class.new(campaign, 'import_id' => import.id).call

    expect(identity[:logo_url]).to be_nil
  end

  it 'gives no identity when BRAND_KITS_ENABLED is off' do
    with_modified_env(BRAND_KITS_ENABLED: 'false') do
      expect(described_class.new(campaign, 'kit_id' => kit.id).call).to eq([nil, {}])
    end
  end
end

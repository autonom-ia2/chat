require 'rails_helper'

RSpec.describe BrandKits::PromptPayload do
  let(:kit) { create(:brand_kit, name: 'Hub2You') }

  it 'gives the AI the palette roles, the font stacks with Arial fallback, socials and footer' do
    kit.update!(appearance: kit.appearance.deep_merge('typography' => { 'google_font_url' => 'https://fonts.googleapis.com/css2?family=Roboto' },
                                                      'logo_url' => 'https://hub2you.ai/logo.png'))

    payload = described_class.new(kit).to_h

    expect(payload[:name]).to eq('Hub2You')
    expect(payload[:palette]).to include(primary: '#ff1f2d', ink: '#111827', on_primary: '#111827')
    expect(payload[:typography]).to eq(
      heading_font: 'MuseoModerno', body_font: 'Roboto', fallback: 'Arial, Helvetica, sans-serif',
      heading_stack: "'MuseoModerno', Arial, Helvetica, sans-serif", body_stack: "'Roboto', Arial, Helvetica, sans-serif",
      google_font_url: 'https://fonts.googleapis.com/css2?family=Roboto'
    )
    expect(payload[:logo_url]).to eq('https://hub2you.ai/logo.png')
    expect(payload[:social_links]).to eq([{ network: 'linkedin', url: 'https://www.linkedin.com/company/hub2you-insurtech' }])
    expect(payload[:footer]).to eq(company_name: 'Hub2You', address: 'Av. Paulista, 1000 - São Paulo/SP')
  end

  it 'prefers the stored logo (public ActiveStorage URL) over the remote one' do
    kit.logo.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'logo.png', content_type: 'image/png')

    expect(described_class.new(kit).to_h[:logo_url]).to include('/rails/active_storage/blobs/')
  end

  it 'falls back to Arial alone when the kit has no font' do
    kit.update!(appearance: kit.appearance.merge('typography' => {}))

    expect(described_class.new(kit).to_h[:typography]).to eq(fallback: 'Arial, Helvetica, sans-serif',
                                                             heading_stack: 'Arial, Helvetica, sans-serif',
                                                             body_stack: 'Arial, Helvetica, sans-serif')
  end

  it 'accepts an unsaved import proposal' do
    proposal = { 'name' => 'Aurora', 'appearance' => kit.appearance.merge('extra' => 1) }

    expect(described_class.new(proposal).to_h).to include(name: 'Aurora', palette: hash_including(primary: '#ff1f2d'))
  end
end

require 'rails_helper'

RSpec.describe BrandKits::PromptPayload do
  let(:kit) { create(:brand_kit, name: 'Hub2You') }

  it 'gives the AI the light colors by default, the font stacks with Arial fallback, socials and footer' do
    kit.update!(appearance: kit.appearance.deep_merge('typography' => { 'google_font_url' => 'https://fonts.googleapis.com/css2?family=Roboto' },
                                                      'logo_url' => 'https://hub2you.ai/logo.png'))

    payload = described_class.new(kit).to_h

    expect(payload[:name]).to eq('Hub2You')
    expect(payload[:mode]).to eq('light')
    expect(payload[:palette]).to include(primary: '#c8102e', ink: '#0b243f', band: '#0b243f', on_primary: '#ffffff')
    expect(payload[:typography]).to eq(
      heading_font: 'MuseoModerno', body_font: 'Roboto', fallback: 'Arial, Helvetica, sans-serif',
      heading_stack: "'MuseoModerno', Arial, Helvetica, sans-serif", body_stack: "'Roboto', Arial, Helvetica, sans-serif",
      google_font_url: 'https://fonts.googleapis.com/css2?family=Roboto'
    )
    expect(payload[:logo_url]).to eq('https://hub2you.ai/logo.png')
    expect(payload[:social_links]).to eq([{ network: 'linkedin', url: 'https://www.linkedin.com/company/hub2you-insurtech' }])
    expect(payload[:footer]).to eq(company_name: 'Hub2You', address: 'Av. Paulista, 1000 - São Paulo/SP')
  end

  it 'gives the dark colors when the e-mail chose the dark version' do
    payload = described_class.new(kit, mode: 'dark').to_h

    expect(payload[:mode]).to eq('dark')
    expect(payload[:palette]).to include(background: '#0b243f', ink: '#ffffff')
  end

  it 'falls back to the light version for an unknown mode' do
    expect(described_class.new(kit, mode: 'neon').to_h[:mode]).to eq('light')
  end

  it 'builds the one locked footer with the identity line of the kit' do
    footer = described_class.new(kit).to_h[:footer_mjml]

    expect(footer).to start_with('<mj-section css-class="footer-locked"')
    expect(footer).to include('Hub2You · Av. Paulista, 1000 - São Paulo/SP')
    expect(footer.scan('{{ unsubscribe_url }}').size).to eq(1)
  end

  it 'prefers the stored logo (public ActiveStorage URL on the installation host) over the remote one' do
    kit.logo.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'logo.png', content_type: 'image/png')

    with_modified_env FRONTEND_URL: 'https://app.example.com' do
      expect(described_class.new(kit).to_h[:logo_url]).to start_with('https://app.example.com/rails/active_storage/blobs/')
    end
  end

  it 'uses the logo URL it is given (an unsaved site whose logo was stored with the campaign)' do
    expect(described_class.new(kit, logo_url: 'https://app.example.com/l.png').to_h[:logo_url]).to eq('https://app.example.com/l.png')
  end

  it 'falls back to Arial alone when the kit has no font' do
    kit.update!(appearance: kit.appearance.merge('typography' => {}))

    expect(described_class.new(kit).to_h[:typography]).to eq(fallback: 'Arial, Helvetica, sans-serif',
                                                             heading_stack: 'Arial, Helvetica, sans-serif',
                                                             body_stack: 'Arial, Helvetica, sans-serif')
  end

  it 'accepts an unsaved import proposal' do
    proposal = { 'name' => 'Aurora', 'appearance' => kit.appearance.merge('extra' => 1) }

    expect(described_class.new(proposal).to_h).to include(name: 'Aurora', palette: hash_including(primary: '#c8102e'))
  end
end

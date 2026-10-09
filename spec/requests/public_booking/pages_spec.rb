require 'rails_helper'

# Casca HTML da página de agendamento (#1189): /book/:slug serve a entrada v2 só para página nova com a flag ligada;
# o resto continua na v1. /b/:code serve sempre a v2. A view não carrega dado da página além do título.
RSpec.describe 'PublicBooking::Pages', type: :request do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:world) { build_booking_world(account: account) }
  let(:profile) { world.profile }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true') { example.run }
  end

  before do
    account.enable_features('crm_booking_v2')
    account.save!
    world.host.update!(email: 'camila.host@example.com')
    # Sem build do Vite no teste: a entrada vira um caminho com o próprio nome.
    allow(ViteRuby.instance.manifest).to receive(:resolve_entries) do |*names, **|
      { scripts: names.map { |name| "/vite-test/assets/#{name}-entry.js" }, imports: [], stylesheets: [] }
    end
  end

  def page
    Nokogiri::HTML(response.body)
  end

  def entry
    page.css('script[src]').map { |tag| tag['src'] }.find { |src| src.include?('-entry.js') }
  end

  it 'serve a v2 para página nova, com idioma, título, noindex e sem dado interno' do
    get "/book/#{profile.slug}", headers: { 'Accept-Language' => 'pt-BR,pt;q=0.9,en;q=0.8' }

    expect(response).to have_http_status(:ok)
    expect(entry).to eq('/vite-test/assets/public_booking_v2-entry.js')
    expect(page.at_css('html')['lang']).to eq('pt-BR')
    expect(page.at_css('title').text).to eq('Conversa de 30 min')
    expect(page.at_css('meta[name="robots"]')['content']).to eq('noindex, nofollow')
    expect(page.at_css('meta[name="viewport"]')['content']).to eq('width=device-width, initial-scale=1')
  end

  it 'não põe dado interno na casca da v2' do
    get "/book/#{profile.slug}"

    ['camila.host@example.com', world.contact.phone_number].each { |secret| expect(response.body).not_to include(secret) }
  end

  it 'segue o idioma do navegador e, sem ele, o da conta' do
    get "/book/#{profile.slug}", headers: { 'Accept-Language' => 'en-US,en;q=0.9' }
    expect(page.at_css('html')['lang']).to eq('en')

    get "/book/#{profile.slug}", headers: { 'Accept-Language' => 'de-DE' }
    expect(page.at_css('html')['lang']).to eq('pt-BR')
  end

  it 'não mostra o título de página pausada' do
    profile.update!(enabled: false)

    get "/book/#{profile.slug}"

    expect(entry).to eq('/vite-test/assets/public_booking_v2-entry.js')
    expect(page.at_css('title').text).not_to eq('Conversa de 30 min')
  end

  # M1: o slug-base de página per_agent só existe na prévia; sem passar o token a casca caía na v1.
  it 'serve a v2 na prévia do slug-base de página per_agent e a v1 sem prévia válida' do
    profile.update!(assignment_mode: :per_agent, enabled: false)
    profile.agent_booking_links.create!(account: account, agent: world.host)
    preview = Crm::BookingV2::Tokens.generate('preview', { 'p' => profile.id }, expires_in: 1.hour)

    get "/book/#{profile.slug}", params: { preview: preview }
    expect(entry).to eq('/vite-test/assets/public_booking_v2-entry.js')

    [nil, 'lixo', Crm::BookingV2::Tokens.generate('form', { 'p' => profile.id }, expires_in: 1.hour)].each do |token|
      get "/book/#{profile.slug}", params: { preview: token }.compact
      expect(entry).to eq('/vite-test/assets/public_booking-entry.js'), token.inspect
    end
  end

  it 'serve a v1 para página antiga, slug desconhecido, flag desligada e confirmação da v1' do
    inbox = create(:channel_email, account: account, provider: 'google', calendar_enabled: true).inbox
    legacy = create_booking_profile(account: account, host: world.host, page_version: Crm::AgentBookingProfile::LEGACY_PAGE, inbox: inbox)
    ["/book/#{legacy.slug}", "/book/#{SecureRandom.uuid}", "/book/#{profile.slug}/confirm"].each do |path|
      get path
      expect(entry).to eq('/vite-test/assets/public_booking-entry.js'), path
    end

    account.disable_features('crm_booking_v2')
    account.save!
    get "/book/#{profile.slug}"
    expect(entry).to eq('/vite-test/assets/public_booking-entry.js')
  end

  it 'serve a v2 no link por cliente, mesmo para código desconhecido, sem expor o convite' do
    invite = create_booking_invite(world: world)

    [invite.code, 'NAOEXISTE'].each do |code|
      get "/b/#{code}"
      expect(response).to have_http_status(:ok)
      expect(entry).to eq('/vite-test/assets/public_booking_v2-entry.js')
      expect(page.at_css('meta[name="robots"]')['content']).to eq('noindex, nofollow')
    end
    expect(response.body).not_to include(world.contact.name)
  end
end

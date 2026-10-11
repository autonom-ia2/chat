require 'rails_helper'

# Link curto e prévia do link (#1282). `/a/<nome>` e `/a/<nome>/<pessoa>` servem a casca v2 com o slug resolvido; as
# três rotas públicas (`/a`, `/book`, `/b`) levam Open Graph só com dados da página, e neutro quando a página não
# pode ser marcada.
RSpec.describe 'PublicBooking short links and link preview', type: :request do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:world) { build_booking_world(account: account, host_name: 'Ana Souza') }
  let(:profile) { world.profile }
  let(:colleague) { create(:user, account: account, role: :agent, name: 'Bruno Lima') }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true', 'FRONTEND_URL' => 'https://chat.exemplo.com') do
      example.run
    end
  end

  before do
    account.enable_features('crm_booking_v2')
    account.save!
    profile.update!(short_name: 'clinica-viva', title: 'Avaliação gratuita')
    allow(GlobalConfig).to receive(:get).and_return('INSTALLATION_NAME' => 'Central de Atendimento')
    allow(ViteRuby.instance.manifest).to receive(:resolve_entries) do |*names, **|
      { scripts: names.map { |name| "/vite-test/assets/#{name}-entry.js" }, imports: [], stylesheets: [] }
    end
  end

  def html
    Nokogiri::HTML(response.body)
  end

  def meta(property)
    html.at_css("meta[property='#{property}']")&.[]('content')
  end

  def slug_meta
    html.at_css('meta[name="booking-slug"]')&.[]('content')
  end

  def entry
    html.css('script[src]').map { |tag| tag['src'] }.find { |src| src.include?('-entry.js') }
  end

  def per_agent!
    Crm::BookingV2::PagePeople.new(profile).assign!([world.host.id, colleague.id])
    Crm::BookingV2::PersonNames.new(profile).assign_missing!
    profile.reload
  end

  def expect_neutral_preview
    expect(meta('og:title')).to eq('Central de Atendimento')
    expect(meta('og:description')).to be_nil
    expect(meta('og:image')).to eq('https://chat.exemplo.com/booking-preview.png')
    expect(response.body).not_to include('Avaliação gratuita')
  end

  describe 'GET /a/:name' do
    it 'abre a página v2 com o slug resolvido, o título e a prévia da página' do
      get '/a/clinica-viva'

      expect(response).to have_http_status(:ok)
      expect(entry).to eq('/vite-test/assets/public_booking_v2-entry.js')
      expect(slug_meta).to eq(profile.slug)
      expect(html.at_css('title').text).to eq('Avaliação gratuita')
    end

    it 'leva título, descrição, endereço e tipo na prévia' do
      get '/a/clinica-viva'

      expect(meta('og:title')).to eq('Avaliação gratuita')
      expect(meta('og:description')).to eq('30 min · Vídeo no WhatsApp · Escolha o melhor horário para você')
      expect(meta('og:url')).to eq('https://chat.exemplo.com/a/clinica-viva')
      expect(meta('og:type')).to eq('website')
    end

    it 'aponta a imagem de 1200×630 no endereço com a versão, e o cartão grande do Twitter' do
      get '/a/clinica-viva'

      version = Crm::BookingV2::PreviewImage::Content.new(Crm::BookingV2::LinkPreview.for_slug(profile.slug)).version
      expect(meta('og:image')).to eq("https://chat.exemplo.com/book/#{profile.slug}/preview/#{version}.png")
      expect([meta('og:image:width'), meta('og:image:height')]).to eq(%w[1200 630])
      expect(html.at_css('meta[name="twitter:card"]')['content']).to eq('summary_large_image')
    end

    it 'põe a prévia dentro do head, antes dos scripts' do
      get '/a/clinica-viva'

      head = response.body[0...response.body.index('</head>')]
      expect(head.index('og:title')).to be < head.index('<script')
    end

    it 'não liga para maiúsculas no nome' do
      get '/a/Clinica-Viva'

      expect(slug_meta).to eq(profile.slug)
    end

    it 'responde a mesma casca neutra, sem slug, para nome que não existe, do sistema ou mal formado' do
      ['/a/nao-existe', '/a/admin', '/a/book', '/a/ab', "/a/#{profile.slug}", '/a/clinica-viva/ninguem'].each do |path|
        get path

        expect(response).to have_http_status(:ok), path
        expect(entry).to eq('/vite-test/assets/public_booking_v2-entry.js'), path
        expect(slug_meta).to be_nil, path
        expect_neutral_preview
      end
    end

    it 'não acha a página com a flag da conta desligada' do
      account.disable_features('crm_booking_v2')
      account.save!

      get '/a/clinica-viva'

      expect(slug_meta).to be_nil
      expect_neutral_preview
    end

    it 'entrega o slug da página pausada (a página mostra o aviso de pausa), com prévia neutra e sem o título' do
      profile.update!(enabled: false)

      get '/a/clinica-viva'

      expect(slug_meta).to eq(profile.slug)
      expect(html.at_css('title').text).not_to eq('Avaliação gratuita')
      expect_neutral_preview
    end

    it 'escapa o título que a pessoa escreveu' do
      profile.update!(title: 'Corte "premium" <b>& barba</b>')

      get '/a/clinica-viva'

      expect(meta('og:title')).to eq('Corte "premium" <b>& barba</b>')
      expect(response.body).not_to include('<b>& barba</b>')
    end

    it 'corta título e descrição compridos' do
      profile.update!(title: "Consulta #{'muito ' * 20}longa", locations: [{ 'type' => 'in_person', 'address' => 'Rua A', 'label' => 'Sala ' * 30 }])

      get '/a/clinica-viva'

      expect(meta('og:title').length).to be <= 60
      expect(meta('og:description').length).to be <= 90
    end
  end

  describe 'GET /a/:name/:person' do
    before { per_agent! }

    it 'abre o link da pessoa e diz quem atende na prévia' do
      get '/a/clinica-viva/bruno'

      link = profile.agent_booking_links.find_by(agent_id: colleague.id)
      expect(slug_meta).to eq(link.slug)
      expect(meta('og:title')).to eq('Avaliação gratuita')
      expect(meta('og:description')).to start_with("Com #{colleague.available_name} · 30 min")
      expect(meta('og:url')).to eq('https://chat.exemplo.com/a/clinica-viva/bruno')
    end

    it 'não abre nem entrega o slug do endereço-base da página com um link por pessoa' do
      get '/a/clinica-viva'

      expect(slug_meta).to be_nil
      expect(response.body).not_to include(profile.slug)
      expect_neutral_preview
    end

    it 'não entrega o slug de um link antigo depois que a página volta a ter um responsável só' do
      old_slug = profile.agent_booking_links.find_by(agent_id: colleague.id).slug
      Crm::BookingV2::PagePeople.new(profile).assign!([world.host.id])

      get '/a/clinica-viva/bruno'

      expect(slug_meta).to be_nil
      expect(response.body).not_to include(old_slug)
      expect_neutral_preview
    end

    it 'trata o link da pessoa desligada como pausado: prévia neutra' do
      profile.agent_booking_links.find_by(agent_id: colleague.id).update!(enabled: false)

      get '/a/clinica-viva/bruno'

      expect_neutral_preview
    end
  end

  describe 'GET /book/:slug' do
    it 'continua funcionando e ganha a mesma prévia' do
      get "/book/#{profile.slug}"

      expect(response).to have_http_status(:ok)
      expect(entry).to eq('/vite-test/assets/public_booking_v2-entry.js')
      expect(slug_meta).to be_nil
      expect(meta('og:title')).to eq('Avaliação gratuita')
      expect(meta('og:url')).to eq("https://chat.exemplo.com/book/#{profile.slug}")
    end

    it 'dá prévia neutra para slug desconhecido e página pausada' do
      get "/book/#{SecureRandom.uuid}"
      expect_neutral_preview

      profile.update!(enabled: false)
      get "/book/#{profile.slug}"
      expect_neutral_preview
    end
  end

  describe 'GET /b/:code' do
    let(:invite) { create_booking_invite(world: world) }

    before { world.contact.update!(name: 'Zuleica Pacheco', phone_number: '+5511987650001', email: 'zuleica@example.com') }

    it 'mostra a prévia da página dona do convite, sem nenhum dado do cliente' do
      get "/b/#{invite.code}"

      expect(response).to have_http_status(:ok)
      expect(meta('og:title')).to eq('Avaliação gratuita')
      expect(meta('og:description')).to eq('30 min · Vídeo no WhatsApp · Escolha o melhor horário para você')
      expect(meta('og:url')).to eq("https://chat.exemplo.com/b/#{invite.code}")
      expect(meta('og:image')).to start_with("https://chat.exemplo.com/book/#{profile.slug}/preview/")
      ['Zuleica', 'Pacheco', '987650001', '8765', 'zuleica@example.com'].each { |secret| expect(response.body).not_to include(secret) }
    end

    it 'dá prévia neutra para código desconhecido, convite cancelado ou vencido e página pausada' do
      get '/b/NAOEXISTE'
      expect_neutral_preview

      canceled = create_booking_invite(world: world, canceled_at: Time.current)
      expired = create_booking_invite(world: world, expires_at: 1.minute.ago)
      [canceled, expired].each do |other|
        get "/b/#{other.code}"
        expect_neutral_preview
      end

      profile.update!(enabled: false)
      get "/b/#{invite.code}"
      expect_neutral_preview
    end
  end
end

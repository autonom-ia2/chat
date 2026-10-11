require 'rails_helper'

# Imagem de prévia do link (#1282): `GET /book/:slug/preview/:version.png`. PNG de 1200×630 abaixo de 600 KB, um
# dos três desenhos, guardada depois do primeiro pedido; imagem neutra (nunca 500 nem 404) quando não há página ou o
# desenho falha; versão que não é a atual só redireciona. Os exemplos que desenham precisam da libvips de verdade (a
# imagem de produção e o CI a instalam).
RSpec.describe 'PublicBooking::PreviewImages', type: :request do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:world) { build_booking_world(account: account, host_name: 'Ana Souza') }
  let(:profile) { world.profile }
  let(:neutral) { Rails.public_path.join('booking-preview.png').binread }
  let(:png_signature) { "\x89PNG\r\n\x1A\n".b }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true', 'FRONTEND_URL' => 'https://chat.exemplo.com') do
      example.run
    end
  end

  before do
    account.enable_features('crm_booking_v2')
    account.save!
  end

  def vips!
    require 'image_processing/vips'
  rescue LoadError => e
    skip "libvips indisponível nesta máquina: #{e.class}"
  end

  def content_for(slug)
    Crm::BookingV2::PreviewImage::Content.new(Crm::BookingV2::LinkPreview.for_slug(slug))
  end

  def image_path(slug, version = content_for(slug).version)
    "/book/#{slug}/preview/#{version}.png"
  end

  def avatar_upload
    { io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png' }
  end

  def expect_page_image
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('image/png')
    expect_png_of_the_page(response.body.b)
  end

  def expect_png_of_the_page(bytes)
    expect(bytes).to start_with(png_signature)
    expect(bytes.bytesize).to be < 600.kilobytes
    expect(bytes).not_to eq(neutral)
    image = Vips::Image.new_from_buffer(bytes, '')
    expect([image.width, image.height]).to eq([1200, 630])
  end

  # Página que não existe para o público: neutra com cache curto. Página que tem imagem própria mas não pôde ser
  # desenhada agora: neutra sem cache, para ninguém guardar a neutra no endereço dela.
  def expect_neutral_image(cached: true)
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('image/png')
    expect(response.body.b).to eq(neutral)
    expect_neutral_cache(response.headers, cached)
  end

  def expect_neutral_cache(headers, cached)
    expect(headers['Cache-Control']).to cached ? include('max-age=300', 'public') : eq('no-store')
    expect(headers['ETag']).to be_nil
  end

  it 'tem a imagem neutra fixa em public/, PNG abaixo de 600 KB' do
    expect(neutral).to start_with(png_signature)
    expect(neutral.bytesize).to be < 600.kilobytes
  end

  describe 'os três desenhos' do
    before { vips! }

    it 'C: página sem logo nem foto' do
      expect(content_for(profile.slug).design).to eq(:light)

      get image_path(profile.slug)
      expect_page_image
    end

    it 'A: página com logo' do
      profile.logo.attach(avatar_upload)
      expect(content_for(profile.slug).design).to eq(:brand)

      get image_path(profile.slug)
      expect_page_image
    end

    it 'B: link de uma pessoa que tem foto' do
      colleague = create(:user, account: account, role: :agent, name: 'Bruno Lima')
      colleague.avatar.attach(avatar_upload)
      Crm::BookingV2::PagePeople.new(profile).assign!([world.host.id, colleague.id])
      links = profile.agent_booking_links.index_by(&:agent_id)

      expect(content_for(links[colleague.id].slug).design).to eq(:person)
      expect(content_for(links[world.host.id].slug).design).to eq(:light)
      get image_path(links[colleague.id].slug)
      expect_page_image
    end

    it 'aguenta título enorme, com marcação e cor fora do padrão' do
      profile.update!(title: "<b>Consulta</b> & retorno #{'muito ' * 35}longa", brand: { 'color' => '#FFEE00' })

      get image_path(profile.slug)
      expect_page_image
    end
  end

  describe 'cache' do
    before { vips! }

    it 'guarda a imagem e não desenha de novo no pedido seguinte' do
      get image_path(profile.slug)
      first = response.body
      expect(profile.reload.preview_image).to be_attached

      allow(Crm::BookingV2::PreviewImage::Renderer).to receive(:png).and_raise('não era para desenhar de novo')
      get image_path(profile.slug)
      expect(response.body).to eq(first)
      expect(response.headers['Cache-Control'].split(', ')).to contain_exactly('max-age=31556952', 'public', 'immutable')
    end

    it 'muda de versão e redesenha quando a marca muda, deixando um anexo só' do
      old_version = content_for(profile.slug).version
      get image_path(profile.slug, old_version)
      old = response.body

      profile.update!(title: 'Outro nome', brand: { 'color' => '#B3263E' })
      expect(content_for(profile.slug).version).not_to eq(old_version)

      get image_path(profile.slug)
      expect_page_image
      expect(response.body).not_to eq(old)
      expect(ActiveStorage::Attachment.where(record: profile, name: 'preview_image').count).to eq(1)
    end

    it 'redireciona a versão antiga ou inventada para a atual, sem ler nem desenhar' do
      allow(Crm::BookingV2::PreviewImage::Store).to receive(:new).and_raise('não era para abrir o armazenamento')

      ['versao-antiga', 'x' * 200].each do |version|
        get "/book/#{profile.slug}/preview/#{version}.png"

        expect(response).to have_http_status(:found)
        expect(response.headers['Location']).to end_with(image_path(profile.slug))
        expect(response.headers['Cache-Control']).to include('max-age=300')
        expect(response.headers['Cache-Control']).not_to include('immutable')
      end
    end

    it 'desenha de novo quando o arquivo guardado some do armazenamento' do
      get image_path(profile.slug)
      profile.reload.preview_image.blob.service.delete(profile.preview_image.blob.key)

      get image_path(profile.slug)
      expect_page_image
    end

    it 'responde 304, sem ler o arquivo, a quem já tem a imagem' do
      get image_path(profile.slug)
      etag = response.headers['ETag']
      expect(etag).to be_present

      allow(Crm::BookingV2::PreviewImage::Store).to receive(:new).and_raise('não era para abrir o armazenamento')
      get image_path(profile.slug), headers: { 'If-None-Match' => etag }
      expect(response).to have_http_status(:not_modified)
    end

    it 'troca para o desenho claro, e guarda, quando a logo não pode ser lida' do
      profile.logo.attach(io: StringIO.new('isto não é uma imagem'), filename: 'logo.png', content_type: 'image/png')
      expect(content_for(profile.slug).design).to eq(:brand)

      get image_path(profile.slug)
      expect_page_image
      expect(profile.reload.preview_image).to be_attached
    end

    it 'não muda de versão quando muda algo que não aparece na imagem' do
      before_change = content_for(profile.slug).version
      profile.update!(description: 'Outra descrição', buffer_minutes: 15)

      expect(content_for(profile.slug).version).to eq(before_change)
    end
  end

  describe 'imagem neutra, nunca erro' do
    # Calculadas antes de cada exemplo: um deles desliga a flag, e sem página não há chave para calcular.
    let!(:store) { Crm::BookingV2::PreviewImage::Store.new(content_for(profile.slug)) }
    let!(:redis_keys) { [store.lock_key, store.failure_key] }

    after { redis_keys.each { |key| Redis::Alfred.delete(key) } }

    it 'para slug desconhecido, página pausada, antiga e conta sem a flag' do
      inbox = create(:channel_email, account: account, provider: 'google', calendar_enabled: true).inbox
      legacy = create_booking_profile(account: account, host: world.host, page_version: Crm::AgentBookingProfile::LEGACY_PAGE, inbox: inbox)
      paused = create_booking_profile(account: account, host: world.host, enabled: false)

      [SecureRandom.uuid, legacy.slug, paused.slug].each do |slug|
        get "/book/#{slug}/preview/qualquer.png"
        expect_neutral_image
        expect(response.headers['Location']).to be_nil
      end

      account.disable_features('crm_booking_v2')
      account.save!
      get "/book/#{profile.slug}/preview/qualquer.png"
      expect_neutral_image
    end

    it 'quando o desenho falha ou a libvips não existe, sem cache e sem guardar nada' do
      [StandardError.new('quebrou'), LoadError.new('cannot load such file -- vips')].each do |failure|
        Redis::Alfred.delete(store.failure_key)
        allow(Crm::BookingV2::PreviewImage::Renderer).to receive(:png).and_raise(failure)

        get image_path(profile.slug)
        expect_neutral_image(cached: false)
        expect(profile.reload.preview_image).not_to be_attached
      end
    end

    it 'não tenta desenhar de novo a cada pedido depois de uma falha, e solta a trava' do
      allow(Crm::BookingV2::PreviewImage::Renderer).to receive(:png).and_raise('quebrou')

      3.times { get image_path(profile.slug) }

      expect_neutral_image(cached: false)
      expect(Crm::BookingV2::PreviewImage::Renderer).to have_received(:png).once
      expect(Redis::Alfred.exists?(store.lock_key)).to be(false)
    end

    it 'quando outro pedido já está desenhando a mesma imagem, sem mexer na trava dele' do
      Redis::Alfred.set(store.lock_key, 'outro-pedido', nx: true, ex: 30)
      allow(Crm::BookingV2::PreviewImage::Renderer).to receive(:png).and_raise('não era para desenhar')

      get image_path(profile.slug)

      expect_neutral_image(cached: false)
      expect(Redis::Alfred.get(store.lock_key)).to eq('outro-pedido')
    end

    it 'quando a imagem passa do teto de tamanho' do
      allow(Crm::BookingV2::PreviewImage::Renderer).to receive(:png).and_return('x' * (600.kilobytes + 1))

      get image_path(profile.slug)
      expect_neutral_image(cached: false)
    end
  end

  it 'só responde a PNG' do
    get "/book/#{profile.slug}/preview/qualquer.jpg"

    expect(response).to have_http_status(:not_found)
  end
end

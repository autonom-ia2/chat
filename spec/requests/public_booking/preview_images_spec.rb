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
    clear_draw_marks
  end

  after { clear_draw_marks }

  # Vagas do teto global e a marca da varredura (#1303) ficam no Redis de teste: cada exemplo começa sem elas.
  def clear_draw_marks
    draw_limit = Crm::BookingV2::PreviewImage::DrawLimit
    draw_limit::MAX_LIMIT.times { |index| Redis::Alfred.delete(draw_limit.slot_key(index)) }
    Redis::Alfred.delete(draw_limit.account_key(account.id))
    Redis::Alfred.delete(Crm::BookingV2::PreviewImage::Warmup.sweep_key)
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
      # Arquivo que entrou antes da conferência de conteúdo (#1303): hoje o envio dele seria recusado.
      attach_unchecked(profile, :logo, 'isto não é uma imagem')
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

  # Teto global (#1303): a trava de antes era por página, então um robô pedindo páginas diferentes punha um desenho
  # em cada thread do web. O desenho é trocado por um PNG pronto: estes exemplos não precisam da libvips.
  describe 'teto global de desenhos' do
    let(:draw_limit) { Crm::BookingV2::PreviewImage::DrawLimit }
    let(:warmup) { Crm::BookingV2::PreviewImage::Warmup }
    let(:warm_job) { Crm::BookingV2::PreviewImageWarmJob }
    let(:sweep_job) { Crm::BookingV2::PreviewImageSweepJob }
    let(:drawn) { Rails.root.join('spec/assets/avatar.png').binread }
    let(:store) { Crm::BookingV2::PreviewImage::Store.new(content_for(profile.slug)) }

    before { allow(Crm::BookingV2::PreviewImage::Renderer).to receive(:png).and_return(drawn) }

    after do
      Crm::AgentBookingProfile.where(account: account).find_each { |page| Redis::Alfred.delete(warmup.queued_key(page.id)) }
      [store.lock_key, store.failure_key].each { |key| Redis::Alfred.delete(key) }
    end

    # Dois desenhos em andamento em outros processos.
    def fill_slots
      draw_limit.limit.times { |index| Redis::Alfred.set(draw_limit.slot_key(index), 'outro-processo', nx: true, ex: 30) }
    end

    def slots_taken
      draw_limit::MAX_LIMIT.times.count { |index| Redis::Alfred.exists?(draw_limit.slot_key(index)) }
    end

    it 'cheio: responde a neutra sem cache, sem desenhar, sem marcar falha e soltando a trava da página' do
      fill_slots

      get image_path(profile.slug)

      expect_neutral_image(cached: false)
      expect(Crm::BookingV2::PreviewImage::Renderer).not_to have_received(:png)
      expect(Redis::Alfred.exists?(store.failure_key)).to be(false)
      expect(Redis::Alfred.exists?(store.lock_key)).to be(false)
      expect(profile.reload.preview_image).not_to be_attached
    end

    it 'cheio: registra o motivo e põe a página na fila uma vez só, por mais que o robô insista' do
      fill_slots
      allow(Rails.logger).to receive(:info)

      expect { 5.times { get image_path(profile.slug) } }.to have_enqueued_job(warm_job).with(profile.id).once

      expect(Rails.logger).to have_received(:info).with('Booking preview image not drawn: draw_limit').exactly(5).times
    end

    it 'um robô pedindo páginas diferentes não desenha além do teto' do
      pages = Array.new(4) { create_booking_profile(account: account, host: world.host) }
      fill_slots

      pages.each do |page|
        get image_path(page.slug)
        expect_neutral_image(cached: false)
      end

      expect(Crm::BookingV2::PreviewImage::Renderer).not_to have_received(:png)
      expect(slots_taken).to eq(draw_limit.limit)
    end

    it 'com uma vaga livre desenha, guarda e solta a vaga' do
      Redis::Alfred.set(draw_limit.slot_key(0), 'outro-processo', nx: true, ex: 30)

      get image_path(profile.slug)

      expect(response.body.b).to eq(drawn)
      expect(profile.reload.preview_image).to be_attached
      expect(slots_taken).to eq(1)
    end

    it 'solta a vaga quando o desenho falha' do
      allow(Crm::BookingV2::PreviewImage::Renderer).to receive(:png).and_raise('quebrou')

      get image_path(profile.slug)

      expect_neutral_image(cached: false)
      expect(slots_taken).to eq(0)
    end

    # O prazo de cada vaga é conferido no spec do DrawLimit; aqui, o prazo vence entre um pedido e outro.
    it 'vaga de processo que morreu expira, e o pedido seguinte desenha' do
      keys = Array.new(draw_limit.limit) { |index| draw_limit.slot_key(index) }
      keys.each { |key| Redis::Alfred.set(key, 'processo-morto', nx: true, ex: 30) }
      get image_path(profile.slug)
      expect_neutral_image(cached: false)

      keys.each { |key| Redis::Alfred.with { |conn| conn.pexpire(key, 1) } }
      sleep 0.05
      get image_path(profile.slug)
      expect(response.body.b).to eq(drawn)
    end

    it 'uma conta que já está desenhando não pega a segunda vaga; outra conta pega' do
      Redis::Alfred.set(draw_limit.account_key(account.id), 'outro-processo', nx: true, ex: 30)
      get image_path(profile.slug)
      expect_neutral_image(cached: false)

      other_account = create(:account)
      other_account.enable_features('crm_booking_v2')
      other_account.save!
      other = create_booking_profile(account: other_account, host: create(:user, account: other_account, role: :agent))
      get image_path(other.slug)

      expect(response.body.b).to eq(drawn)
      expect(slots_taken).to eq(0)
    ensure
      Redis::Alfred.delete(draw_limit.account_key(other_account.id)) if other_account
    end

    it 'erro do Redis ao pegar a vaga: neutra sem cache, sem marcar a página como falha' do
      allow(draw_limit).to receive(:with_slot).and_raise(Redis::CannotConnectError, 'sem Redis')

      get image_path(profile.slug)

      expect_neutral_image(cached: false)
      expect(Redis::Alfred.exists?(store.failure_key)).to be(false)
      expect(Redis::Alfred.exists?(store.lock_key)).to be(false)
    end

    it 'servir a imagem já guardada não depende de vaga' do
      get image_path(profile.slug)
      fill_slots

      get image_path(profile.slug)

      expect(response.body.b).to eq(drawn)
      expect(Crm::BookingV2::PreviewImage::Renderer).to have_received(:png).once
    end

    describe 'varredura quando o desenho muda' do
      it 'o primeiro pedido sem imagem guardada enfileira a varredura, uma vez só' do
        other = create_booking_profile(account: account, host: world.host)

        expect do
          get image_path(profile.slug)
          get image_path(other.slug)
        end.to have_enqueued_job(sweep_job).once
      end

      it 'pedido servido da imagem guardada não enfileira nada' do
        get image_path(profile.slug)
        Redis::Alfred.delete(warmup.sweep_key)

        expect { get image_path(profile.slug) }.not_to have_enqueued_job
      end

      it 'versão nova do desenho: enfileira outra varredura e redesenha a página pedida' do
        get image_path(profile.slug)
        old_key = warmup.sweep_key
        stub_const('Crm::BookingV2::PreviewImage::Content::RENDER_VERSION', Crm::BookingV2::PreviewImage::Content::RENDER_VERSION + 1)

        expect { get image_path(profile.slug) }.to have_enqueued_job(sweep_job).once
        expect(warmup.sweep_key).not_to eq(old_key)
        expect(Crm::BookingV2::PreviewImage::Renderer).to have_received(:png).twice
      ensure
        Redis::Alfred.delete(warmup.sweep_key)
        Redis::Alfred.delete(old_key) if old_key
      end
    end
  end

  it 'só responde a PNG' do
    get "/book/#{profile.slug}/preview/qualquer.jpg"

    expect(response).to have_http_status(:not_found)
  end
end

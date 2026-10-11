require 'rails_helper'

# Imagem de prévia do link (#1282) com a cor livre e a foto de quem atende do #1289: a cor da página pode ser
# qualquer #RRGGBB, inclusive bem clara, e o texto por cima tem de continuar legível. Os exemplos que desenham
# precisam da libvips de verdade.
RSpec.describe Crm::BookingV2::PreviewImage do
  let(:palette) { described_class::Palette }
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:world) { build_booking_world(account: account, host_name: 'Ana Souza') }
  let(:profile) { world.profile }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true', 'FRONTEND_URL' => 'https://chat.exemplo.com') do
      example.run
    end
  end

  before do
    account.enable_features('crm_booking_v2')
    account.save!
  end

  def content
    described_class::Content.new(Crm::BookingV2::LinkPreview.for_slug(profile.reload.slug))
  end

  def image(name = 'avatar.png')
    { io: Rails.root.join('spec/assets', name).open, filename: name, content_type: 'image/png' }
  end

  def vips!
    require 'image_processing/vips'
  rescue LoadError => e
    skip "libvips indisponível nesta máquina: #{e.class}"
  end

  describe 'cores' do
    it 'o fundo é a cor exata; por cima vai branco em cor escura e escuro em cor clara' do
      expect(palette.fill('#FFE066')).to eq([255, 224, 102])
      expect(palette.on(palette.fill('#FFE066'))).to eq(palette::INK)
      expect(palette.on(palette.fill('#FFFFFF'))).to eq(palette::INK)
      expect(palette.on(palette.fill('#0D2344'))).to eq(palette::WHITE)
      expect(palette.on(palette.fill('amarelo'))).to eq(palette::WHITE)
    end

    it 'qualquer cor tem texto legível por cima (todo texto da imagem é grande: mínimo 3:1; fica acima de 4:1)' do
      steps = (0..255).step(17).to_a
      worst = steps.product(steps, steps).map { |color| palette.contrast(color, palette.on(color)) }.min

      expect(worst).to be >= 4.0
    end

    it 'no desenho A, o texto tem contraste nos DOIS cantos do degradê, em qualquer cor' do
      steps = (0..255).step(17).to_a
      backdrop = described_class::BrandLayout::Backdrop
      worst = steps.product(steps, steps).map { |color| backdrop.for(color).contrast }.min

      # Texto grande pede 3:1.
      expect(worst).to be >= 3.0
      expect(backdrop.for([255, 224, 102]).ink).to eq(palette::INK)
      expect(backdrop.for([13, 35, 68]).ink).to eq(palette::WHITE)
    end

    it 'sobre fundo claro, texto e traços usam a cor escurecida até o AA' do
      ink = palette.brand('#FFE066')

      expect(ink).not_to eq([255, 224, 102])
      expect(palette.contrast(ink, palette::WHITE)).to be >= 4.5
      expect(palette.brand('#0D2344')).to eq([13, 35, 68])
    end
  end

  describe 'versão (impressão digital)' do
    it 'muda quando a cor muda, inclusive entre duas cores claras' do
      profile.update!(brand: { 'color' => '#FFE066' })
      yellow = content.version
      profile.update!(brand: { 'color' => '#FFE067' })

      expect(content.version).not_to eq(yellow)
    end

    it 'não muda com o lado da logo, que não aparece na imagem' do
      profile.update!(brand: { 'color' => '#FFE066', 'logo_align' => 'left' })
      before = content.version
      profile.update!(brand: { 'color' => '#FFE066', 'logo_align' => 'right' })

      expect(content.version).to eq(before)
    end

    it 'muda quando a foto de quem atende muda' do
      world.host.avatar.attach(image)
      with_avatar = content.version
      profile.photo.attach(image('sample.png'))

      expect(content.version).not_to eq(with_avatar)
    end
  end

  describe 'foto de quem atende' do
    def photo_blob
      content.send(:person_photo)&.blob
    end

    it 'segue a ordem da página pública: foto da página, depois a guardada, depois a do perfil' do
      expect(content.design).to eq(:light)

      world.host.avatar.attach(image)
      expect(photo_blob).to eq(world.host.avatar.blob)
      expect(content.design).to eq(:brand)

      availability = Crm::AgentAvailability.create!(account: account, user: world.host)
      availability.booking_photo.attach(image('sample.png'))
      expect(photo_blob).to eq(availability.booking_photo.blob)

      profile.photo.attach(image)
      expect(photo_blob).to eq(profile.reload.photo.blob)
    end

    it 'a logo continua vindo antes da foto no desenho da página' do
      world.host.avatar.attach(image)
      profile.logo.attach(image('sample.png'))

      expect(content.design).to eq(:brand)
      expect(content.art.logo).to be_present
      expect(content.art.photo).to be_nil
    end
  end

  describe 'desenho' do
    before { vips! }

    def draw(color, design: :brand, **extra)
      art = described_class::Art.new(design: design, color: color, title: 'Conversa de 30 min', call: 'Escolher horário',
                                     facts: ['30 minutos', 'Vídeo no WhatsApp'], **extra)
      bytes = described_class::Renderer.png(art)
      out = ENV.fetch('PREVIEW_IMAGE_OUT', nil)
      File.binwrite(File.join(out, "previa-#{design}-#{color.delete('#')}.png"), bytes) if out.present?
      Vips::Image.new_from_buffer(bytes, '')
    end

    def pixel(picture, left, top)
      picture.getpoint(left, top).first(3).map(&:round)
    end

    it 'cor clara: o fundo fica claro (a cor da página, não uma versão escurecida) e a imagem cabe no teto' do
      picture = draw('#FFE066', logo: Rails.root.join('spec/assets/sample.png').binread)

      expect([picture.width, picture.height]).to eq([1200, 630])
      corner = pixel(picture, 20, 300)
      expect(palette.light?(corner)).to be(true)
      expect(palette.contrast(corner, palette::INK)).to be >= 4.5
      # Canto de baixo, o ponto mais escuro do degradê: o texto escuro ainda passa de 3:1.
      expect(palette.contrast(pixel(picture, 1180, 610), palette::INK)).to be >= 3.0
    end

    it 'cor escura: fundo escuro com texto branco, como antes' do
      picture = draw('#0D2344', logo: Rails.root.join('spec/assets/sample.png').binread)

      corner = pixel(picture, 20, 300)
      expect(palette.light?(corner)).to be(false)
      expect(palette.contrast(corner, palette::WHITE)).to be >= 4.5
    end

    it 'desenhos B e C com cor clara: botão na cor exata, sem derrubar o desenho' do
      photo = Rails.root.join('spec/assets/avatar.png').binread

      expect(draw('#FFE066', design: :person, photo: photo, host_line: 'Com Ana').width).to eq(1200)
      expect(draw('#FFE066', design: :light).width).to eq(1200)
    end
  end
end

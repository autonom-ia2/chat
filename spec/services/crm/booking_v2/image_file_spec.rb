require 'rails_helper'

# Conferência do arquivo de imagem das páginas de agendamento (#1303): assinatura comparada byte a byte, o ponto único
# usado pela validação da página e pela identidade salva.
RSpec.describe Crm::BookingV2::ImageFile do
  let(:account) { create(:account) }
  let(:world) { build_booking_world(account: account) }
  let(:page) { world.profile }
  let(:png) { Rails.root.join('spec/assets/avatar.png').binread }
  let(:jpeg) { Rails.root.join('spec/assets/booking_small.jpg').binread }
  let(:webp) { Rails.root.join('spec/assets/booking_small.webp').binread }
  let(:svg) { %(#{' ' * 5000}<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>) }

  describe '.real_type' do
    it 'reconhece PNG, JPEG e WebP pelos primeiros bytes' do
      expect(described_class.real_type(png)).to eq('image/png')
      expect(described_class.real_type(jpeg)).to eq('image/jpeg')
      expect(described_class.real_type(webp)).to eq('image/webp')
    end

    it 'não reconhece SVG, HTML, GIF, RIFF que não é WebP, arquivo cortado, vazio ou nulo' do
      others = [svg, '<!DOCTYPE html><html></html>', "GIF89a#{'x' * 20}", "RIFF#{[36].pack('V')}WAVEfmt ", png.byteslice(0, 6), 'RIFF', '', nil]

      expect(others.map { |bytes| described_class.real_type(bytes) }).to all(be_nil)
    end

    it 'não se engana com a assinatura fora do começo do arquivo' do
      expect(described_class.real_type("<!-- #{png.byteslice(0, 8)} -->")).to be_nil
      expect(described_class.real_type(" #{jpeg}")).to be_nil
    end
  end

  describe '.problem' do
    def with_logo(content, filename: 'logo.png', content_type: 'image/png')
      attach_unchecked(page, :logo, content, filename: filename, content_type: content_type)
    end

    it 'não acha problema em página sem imagem nem em imagem de verdade' do
      expect(described_class.problem(page, :logo)).to be_nil
      expect(described_class.problem(with_logo(png), :logo)).to be_nil
      expect(described_class.problem(with_logo(jpeg, filename: 'l.jpg', content_type: 'image/jpeg'), :logo)).to be_nil
      expect(described_class.problem(with_logo(webp, filename: 'l.webp', content_type: 'image/webp'), :logo)).to be_nil
    end

    it 'tamanho e tipo guardado vêm antes do conteúdo' do
      expect(described_class.problem(with_logo('x' * (Crm::BookingPageSettings::MAX_IMAGE_BYTES + 1)), :logo)).to eq(:image_size)
      expect(described_class.problem(with_logo(svg, filename: 'l.svg', content_type: 'image/svg+xml'), :logo)).to eq(:image_type)
    end

    it 'conteúdo que não é do formato guardado' do
      expect(described_class.problem(with_logo(svg), :logo)).to eq(:image_content)
      expect(described_class.problem(with_logo(jpeg), :logo)).to eq(:image_content)
      expect(described_class.problem(with_logo(''), :logo)).to eq(:image_content)
    end

    describe 'tamanho em pixels (com a libvips)' do
      before do
        require 'image_processing/vips'
      rescue LoadError => e
        skip "libvips indisponível nesta máquina: #{e.class}"
      end

      it 'recusa área acima do teto e lado acima do máximo, e aceita o que cabe' do
        area = Vips::Image.black(5000, 4000).pngsave_buffer
        side = Vips::Image.black(described_class::MAX_SIDE + 1, 1).pngsave_buffer
        fits = Vips::Image.black(4000, 4000).pngsave_buffer

        expect(described_class.problem(with_logo(area), :logo)).to eq(:image_pixels)
        expect(described_class.problem(with_logo(side), :logo)).to eq(:image_pixels)
        expect(described_class.problem(with_logo(fits), :logo)).to be_nil
      end

      it 'recusa, com registro, arquivo com a assinatura certa que a libvips não abre' do
        allow(Rails.logger).to receive(:info)

        expect(described_class.problem(with_logo("#{png.byteslice(0, 8)}#{'lixo' * 100}"), :logo)).to eq(:image_content)
        expect(Rails.logger).to have_received(:info).with('Booking image refused: libvips could not open it (Vips::Error)')
      end
    end

    describe 'sem a libvips' do
      before { allow(Crm::BookingV2::PreviewImage::Canvas).to receive(:load!).and_raise(LoadError, 'cannot load such file -- vips') }

      it 'fora de produção vale a assinatura, com aviso' do
        allow(Rails.logger).to receive(:warn)

        expect(described_class.problem(with_logo(png), :logo)).to be_nil
        expect(Rails.logger).to have_received(:warn).with('Booking image opened without libvips (LoadError): only the file signature was checked')
      end

      it 'em produção recusa, com registro' do
        allow(Rails.env).to receive(:production?).and_return(true)
        allow(Rails.logger).to receive(:error)
        tracker = instance_double(ChatwootExceptionTracker, capture_exception: nil)
        allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

        expect(described_class.problem(with_logo(png), :logo)).to eq(:image_content)
        expect(Rails.logger).to have_received(:error).with('Booking image refused: libvips is missing (LoadError)')
        expect(tracker).to have_received(:capture_exception)
      end
    end

    it 'sem ler o conteúdo, só confere tamanho e tipo guardado' do
      expect(described_class.problem(with_logo(svg), :logo, content: false)).to be_nil
    end

    it 'arquivo que sumiu do armazenamento não serve' do
      with_logo(png)
      page.logo.blob.service.delete(page.logo.blob.key)

      expect(described_class.problem(page, :logo)).to eq(:image_content)
    end

    it 'lê o arquivo que está chegando e o devolve ao começo, para o envio ao armazenamento' do
      io = StringIO.new(png)
      page.logo = { io: io, filename: 'logo.png', content_type: 'image/png' }

      expect(described_class.problem(page, :logo)).to be_nil
      expect(io.pos).to eq(0)
      page.save!
      expect(page.reload.logo.download).to eq(png)
    end
  end

  describe '.validate' do
    it 'põe o erro no registro, com o motivo, e não lê o conteúdo de anexo que não mudou' do
      attach_unchecked(page, :logo, svg)

      described_class.validate(page, %i[logo photo], only_changed: true)
      expect(page.errors).to be_empty

      described_class.validate(page, %i[logo photo], only_changed: false)
      expect(page.errors.details[:logo]).to eq([{ error: :image_content }])
      expect(page.errors[:logo]).to eq(['is not a real PNG, JPEG or WebP image'])
      expect(page.errors[:photo]).to be_empty
    end
  end

  describe 'na validação da página' do
    it 'cobre todos os anexos de imagem da página' do
      expect(Crm::BookingPageSettings::IMAGE_ATTACHMENTS).to eq(%i[logo logo_dark photo])
    end

    it 'recusa o arquivo disfarçado na logo e na foto, e a página segue salvável depois de tirar o arquivo' do
      %i[logo photo].each do |name|
        page.public_send(name).attach(io: StringIO.new(svg), filename: 'imagem.png', content_type: 'image/png')

        expect(page.errors.details[name]).to eq([{ error: :image_content }])
        expect(page.reload.public_send(name)).not_to be_attached
      end
      expect(page.update(title: 'Outro nome')).to be(true)
    end

    it 'página antiga com arquivo ruim guardado ainda salva o resto' do
      attach_unchecked(page, :logo, svg)

      expect(page.update(title: 'Outro nome')).to be(true)
    end
  end
end

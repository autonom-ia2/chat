# Confere de verdade um arquivo de imagem das páginas de agendamento (#1303): logo e foto vão para a página pública, e
# o tipo que o Active Storage guarda (Marcel) vem do nome do arquivo quando o conteúdo não é reconhecido — um SVG ou
# HTML chamado `logo.png` passava como `image/png`.
#
# É o ponto único da regra. Quem usa: a validação da página (`Crm::BookingPageSettings#validate_images`, para todo
# anexo de `IMAGE_ATTACHMENTS`) e a identidade salva (`Crm::BookingV2::BrandIdentity`), que confere antes de copiar
# para a conta e para quem atende, e antes de pôr numa página.
#
# Em ordem, o arquivo precisa:
# 1. ter até 2 MB (`:image_size`);
# 2. estar guardado como PNG, JPEG ou WebP (`:image_type`);
# 3. começar com a assinatura (os primeiros bytes) desse mesmo formato (`:image_content`), comparada byte a byte;
# 4. abrir na libvips, a mesma que desenha a prévia do link (`:image_content`), com até `Canvas::MAX_SOURCE_PIXELS`
#    pixels e até `MAX_SIDE` em cada lado (`:image_pixels`): 2 MB bem comprimidos cabem centenas de milhões de
#    pixels, que travariam o navegador de quem abre a página. Só o cabeçalho é lido. Onde a libvips não existe
#    (máquina de desenvolvimento) este passo é pulado, com aviso no log; em produção, sem libvips, o arquivo é recusado
#    (a imagem de produção e o CI têm a libvips).
#
# WebP animado passa: é um WebP de verdade, e a prévia do link usa só o primeiro quadro.
class Crm::BookingV2::ImageFile
  PNG = "\x89PNG\r\n\x1A\n".b.freeze
  JPEG = "\xFF\xD8\xFF".b.freeze
  RIFF = 'RIFF'.b.freeze
  WEBP = 'WEBP'.b.freeze
  # No WebP, `RIFF`, quatro bytes de tamanho e só então `WEBP`.
  WEBP_OFFSET = 8
  HEAD_BYTES = 12
  # Lado máximo, em pixels: uma faixa de 10.000.000 × 1 cabe no teto de área e não serve de logo nem de foto.
  MAX_SIDE = 8000
  MESSAGES = {
    image_size: 'is too large',
    image_type: 'must be a PNG, JPEG or WebP image',
    image_content: 'is not a real PNG, JPEG or WebP image',
    image_pixels: 'has too many pixels'
  }.freeze

  # Põe em `record.errors` o problema de cada anexo. `only_changed`: o conteúdo só é lido do anexo que está sendo
  # trocado nesta gravação (salvar o título da página não baixa a logo de novo); tamanho e tipo valem sempre.
  def self.validate(record, names, only_changed:)
    names.each do |name|
      content = !only_changed || record.attachment_changes.key?(name.to_s)
      problem = problem(record, name, content: content)
      record.errors.add(name, problem, message: MESSAGES.fetch(problem)) if problem
    end
  end

  # nil quando o anexo serve (ou não existe); senão, o motivo.
  def self.problem(record, name, content: true)
    new(record, name).problem(content: content)
  end

  # O formato pelos primeiros bytes, ou nil.
  def self.real_type(bytes)
    head = bytes.to_s.byteslice(0, HEAD_BYTES).b
    return 'image/png' if head.start_with?(PNG)
    return 'image/jpeg' if head.start_with?(JPEG)

    'image/webp' if head.start_with?(RIFF) && head.byteslice(WEBP_OFFSET, WEBP.bytesize) == WEBP
  end

  def initialize(record, name)
    @record = record
    @name = name.to_s
    @attachment = record.public_send(name)
  end

  def problem(content:)
    return unless attachment.attached?
    return :image_size if attachment.byte_size > ::Crm::BookingPageSettings::MAX_IMAGE_BYTES
    return :image_type unless ::Crm::BookingPageSettings::IMAGE_TYPES.include?(attachment.content_type)

    content_problem if content
  end

  private

  attr_reader :record, :name, :attachment

  def content_problem
    data = bytes
    return :image_content unless self.class.real_type(data) == attachment.content_type

    size = dimensions(data)
    return :image_content if size.nil?

    :image_pixels if too_big?(*size)
  end

  def too_big?(width, height)
    [width, height].max > MAX_SIDE || width * height > ::Crm::BookingV2::PreviewImage::Canvas::MAX_SOURCE_PIXELS
  end

  # O arquivo que está chegando nesta gravação ainda não foi para o armazenamento: é lido de onde veio (o envio do
  # formulário, ou `{ io: … }`) e devolvido ao começo, para o envio ao armazenamento ler tudo. Anexo já guardado (a
  # identidade salva reaproveita o arquivo de uma página) é baixado inteiro: só chega aqui com até 2 MB, e a libvips
  # abre a partir dos bytes. Arquivo que sumiu do armazenamento não serve.
  def bytes
    change = record.attachment_changes[name]
    source = change.attachable if change.respond_to?(:attachable)
    source = source[:io] if source.is_a?(Hash)
    return source.binread if source.is_a?(Pathname)
    return read(source) if source.respond_to?(:read) && source.respond_to?(:rewind)

    attachment.download
  rescue ActiveStorage::FileNotFoundError
    nil
  end

  def read(source)
    source.rewind
    data = source.read
    source.rewind
    data
  end

  # [largura, altura] lidas do cabeçalho; nil quando o arquivo não abre.
  def dimensions(data)
    ::Crm::BookingV2::PreviewImage::Canvas.load!
    image = Vips::Image.new_from_buffer(data, '')
    [image.width, image.height]
  rescue LoadError => e
    without_vips(e)
  rescue Vips::Error => e
    Rails.logger.info("Booking image refused: libvips could not open it (#{e.class.name})")
    nil
  end

  # Fora de produção, só a assinatura vale ([0, 0]: sem medida). Em produção, a falta da libvips recusa o arquivo.
  def without_vips(error)
    if Rails.env.production?
      Rails.logger.error("Booking image refused: libvips is missing (#{error.class.name})")
      ChatwootExceptionTracker.new(error).capture_exception
      return
    end

    Rails.logger.warn("Booking image opened without libvips (#{error.class.name}): only the file signature was checked")
    [0, 0]
  end
end

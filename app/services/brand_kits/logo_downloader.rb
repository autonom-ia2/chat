# Guarda a logo de um kit (#1076) — só quando a pessoa salva. Baixa pelo SafeFetch (SSRF, 5 MB, 10 s) e
# aceita apenas PNG, JPEG, WebP ou GIF conferidos pela ASSINATURA dos bytes, não pelo cabeçalho; SVG fica
# de fora na v1. O tipo gravado no ActiveStorage é o da assinatura.
class BrandKits::LogoDownloader
  class Error < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  MAX_BYTES = BrandKit::LOGO_MAX_BYTES
  TIMEOUT = 10
  EXTENSIONS = { 'image/png' => 'png', 'image/jpeg' => 'jpg', 'image/webp' => 'webp', 'image/gif' => 'gif' }.freeze

  def self.attach_upload(kit, upload)
    upload.rewind
    bytes = upload.read(MAX_BYTES + 1).to_s
    raise Error, 'logo_too_large' if bytes.bytesize > MAX_BYTES

    attach(kit, bytes)
  end

  def self.attach(kit, bytes)
    content_type = signature(bytes)
    raise Error, 'logo_unsupported_type' if content_type.nil?

    kit.logo.attach(io: StringIO.new(bytes), filename: "logo.#{EXTENSIONS[content_type]}", content_type: content_type, identify: false)
  end

  def self.signature(bytes)
    return 'image/png' if bytes.start_with?("\x89PNG\r\n\x1A\n".b)
    return 'image/jpeg' if bytes.start_with?("\xFF\xD8\xFF".b)
    return 'image/gif' if bytes.start_with?('GIF87a'.b, 'GIF89a'.b)
    return 'image/webp' if bytes.bytesize >= 12 && bytes.byteslice(0, 4) == 'RIFF'.b && bytes.byteslice(8, 4) == 'WEBP'.b

    nil
  end

  def initialize(kit, url)
    @kit = kit
    @url = url
  end

  def perform
    bytes = SafeFetch.fetch(@url, max_bytes: MAX_BYTES, total_timeout: TIMEOUT, max_redirects: 3,
                                  allowed_content_type_prefixes: ['image/'], validate_content_type: false) { |result| result.tempfile.read }
    self.class.attach(@kit, bytes.b)
  rescue SafeFetch::InvalidUrlError, SafeFetch::UnsafeUrlError
    raise Error, 'logo_unsafe_url'
  rescue SafeFetch::FileTooLargeError
    raise Error, 'logo_too_large'
  rescue SafeFetch::Error
    raise Error, 'logo_fetch_failed'
  end
end

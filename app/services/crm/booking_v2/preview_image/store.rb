# Guarda a imagem de prévia pronta (#1282) e só desenha de novo quando a versão muda. A imagem fica anexada ao
# link da pessoa ou à página (`preview_image`, ActiveStorage), com a versão no nome do arquivo: um robô de prévia
# que volta mil vezes lê o arquivo guardado, não manda desenhar.
#
# `bytes` devolve nil quando não há imagem para servir agora, e o controller serve a neutra sem cache:
# - outro pedido já está desenhando a mesma imagem (trava curta no Redis, com dono: só quem pegou a trava a solta);
# - o desenho desta versão falhou há pouco (marca no Redis): não tenta de novo a cada pedido.
#
# O anexo é criado direto (`ActiveStorage::Attachment`), sem salvar a página: salvar rodaria as validações dela, e
# uma página antiga com dado que hoje não passa nunca guardaria a imagem. A troca do anexo antigo pelo novo roda com
# a linha do registro travada, para dois desenhos nunca deixarem dois anexos.
class Crm::BookingV2::PreviewImage::Store
  ATTACHMENT = 'preview_image'.freeze
  LOCK_SECONDS = 30
  FAILURE_SECONDS = 10.minutes.to_i
  LOCK_PREFIX = 'CRM_BOOKING_PREVIEW_IMAGE_LOCK'.freeze
  FAILURE_PREFIX = 'CRM_BOOKING_PREVIEW_IMAGE_FAILED'.freeze

  def initialize(content)
    @content = content
    @record = content.record
  end

  def bytes
    stored || (draw unless failed_recently?)
  end

  def lock_key
    "#{LOCK_PREFIX}::#{record.class.name}::#{record.id}"
  end

  def failure_key
    "#{FAILURE_PREFIX}::#{record.class.name}::#{record.id}::#{content.version}"
  end

  private

  attr_reader :content, :record

  def filename
    "preview-#{content.version}.png"
  end

  # Arquivo que sumiu do armazenamento conta como não guardado: a imagem é desenhada e guardada de novo.
  def stored
    attachment = record.preview_image
    attachment.download if attachment.attached? && attachment.filename.to_s == filename
  rescue ActiveStorage::FileNotFoundError
    nil
  end

  def failed_recently?
    ::Redis::Alfred.exists?(failure_key)
  end

  def draw
    owner = SecureRandom.hex(8)
    return unless ::Redis::Alfred.set(lock_key, owner, nx: true, ex: LOCK_SECONDS)

    begin
      render
    rescue StandardError, LoadError
      ::Redis::Alfred.set(failure_key, '1', ex: FAILURE_SECONDS)
      raise
    ensure
      ::Redis::Alfred.delete_if_equals(lock_key, owner)
    end
  end

  def render
    png = ::Crm::BookingV2::PreviewImage::Renderer.png(content.art)
    raise ::Crm::BookingV2::PreviewImage::TooLarge if png.bytesize > ::Crm::BookingV2::PreviewImage::MAX_BYTES

    keep(png)
    png
  end

  # A imagem já está desenhada: se guardar falhar, ela ainda é servida e o próximo pedido tenta guardar de novo.
  def keep(png)
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(png), filename: filename,
                                                  content_type: ::Crm::BookingV2::PreviewImage::CONTENT_TYPE, identify: false)
    replaced = replace_attachment(blob)
  rescue StandardError => e
    # Não anexou: o arquivo novo não tem dono e sai do armazenamento.
    blob&.purge_later
    ChatwootExceptionTracker.new(e, account: record.account).capture_exception
  else
    replaced.each(&:purge_later)
  end

  # Devolve os arquivos antigos, para saírem do armazenamento só depois de a troca estar gravada.
  def replace_attachment(blob)
    record.with_lock do
      old = ActiveStorage::Attachment.where(record: record, name: ATTACHMENT).includes(:blob).to_a
      old.each(&:delete)
      ActiveStorage::Attachment.create!(record: record, name: ATTACHMENT, blob: blob)
      old.map(&:blob)
    end
  end
end

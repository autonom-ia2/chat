# Guarda a imagem de prévia pronta (#1282) e só desenha de novo quando a versão muda. A imagem fica anexada ao
# link da pessoa ou à página (`preview_image`, ActiveStorage), com a versão no nome do arquivo: um robô de prévia
# que volta mil vezes lê o arquivo guardado, não manda desenhar.
#
# `stored` devolve a imagem guardada na versão atual (ou nil); `draw` desenha e guarda. O pedido web usa os dois; o
# job de pré-aquecimento (#1303) usa `warm`, que desenha o que falta sem baixar a imagem que já está guardada.
# `draw` devolve nil quando não desenhou, e o motivo fica em `skipped`:
# - `:failed_recently`: o desenho desta versão falhou há pouco (marca no Redis): não tenta de novo a cada pedido;
# - `:page_busy`: outro pedido já está desenhando a mesma imagem (trava curta no Redis, com dono: só quem pegou a
#   trava a solta);
# - `:draw_limit`: a instalação (ou a conta) já está no teto de desenhos ao mesmo tempo (`DrawLimit`, #1303).
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

  attr_reader :skipped

  def initialize(content)
    @content = content
    @record = content.record
  end

  # Arquivo que sumiu do armazenamento conta como não guardado: a imagem é desenhada e guardada de novo.
  def stored
    record.preview_image.download if current_attachment?
  rescue ActiveStorage::FileNotFoundError
    nil
  end

  # A trava da página vem antes da vaga global: pedidos repetidos da mesma página não gastam vaga. Só o desenho que
  # falha deixa a marca de falha: teto cheio ou erro do Redis ao pegar a vaga não travam a página por 10 minutos.
  def draw
    return skip(:failed_recently) if failed_recently?

    owner = SecureRandom.hex(8)
    return skip(:page_busy) unless ::Redis::Alfred.set(lock_key, owner, nx: true, ex: LOCK_SECONDS)

    begin
      ::Crm::BookingV2::PreviewImage::DrawLimit.with_slot(record.account_id) { render_or_mark_failure }
    rescue ::Crm::BookingV2::PreviewImage::DrawLimit::Full
      skip(:draw_limit)
    ensure
      ::Redis::Alfred.delete_if_equals(lock_key, owner)
    end
  end

  # Devolve `:stored` (já estava guardada), `:drawn` ou o motivo de não ter desenhado.
  def warm
    return :stored if current_attachment?

    draw ? :drawn : skipped
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

  def current_attachment?
    attachment = record.preview_image
    attachment.attached? && attachment.filename.to_s == filename
  end

  def failed_recently?
    ::Redis::Alfred.exists?(failure_key)
  end

  def skip(reason)
    @skipped = reason
    nil
  end

  def render_or_mark_failure
    render
  rescue StandardError, LoadError
    ::Redis::Alfred.set(failure_key, '1', ex: FAILURE_SECONDS)
    raise
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

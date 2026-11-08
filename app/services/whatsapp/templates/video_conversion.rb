# Conversão do vídeo do topo fora do pedido web (#2370). Em 2 vCPU o ffmpeg leva dezenas de segundos, mais que o limite
# do pedido (Rack::Timeout, 15 s), e tomaria a CPU do painel. O pedido guarda o vídeo original como está e devolve o id;
# o job converte, sobe (`MediaUpload#store`) e grava o resultado; a tela consulta `read` até `done` ou `failed`.
# Estado temporário no Redis, como `Crm::Ai::InteractiveRequest`. O original é apagado no fim e, se o job se perder,
# pela limpeza agendada em `start` (`VideoConversionCleanupJob`).
module Whatsapp::Templates::VideoConversion
  TTL = 30.minutes
  PREFIX = 'whatsapp_templates:video_conversion:'.freeze
  # Uma conversão por vez no servidor: o worker divide 2 vCPU com o painel.
  LOCK_KEY = "#{PREFIX}running".freeze
  LOCK_TTL = (Whatsapp::Templates::VideoForMeta::CONVERT_TIMEOUT + 60).seconds
  KNOWN_FAILURES = [Whatsapp::Templates::Manager::Refused, Whatsapp::Templates::MetaClient::MetaError,
                    Whatsapp::Templates::MetaClient::Unreachable, Whatsapp::Templates::MetaClient::Unsupported].freeze

  module_function

  def start(inbox:, account_user:, file:)
    file.rewind
    blob = ActiveStorage::Blob.create_and_upload!(io: file, filename: file.original_filename.to_s, identify: false,
                                                  metadata: { 'account_id' => inbox.account_id, 'video_conversion' => true })
    id = SecureRandom.uuid
    write(id, 'account_id' => inbox.account_id, 'inbox_id' => inbox.id, 'account_user_id' => account_user.id,
              'blob_id' => blob.id, 'status' => 'pending')
    Whatsapp::Templates::VideoConversionCleanupJob.set(wait: TTL).perform_later(blob.id)
    Whatsapp::Templates::VideoConversionJob.perform_later(id)
    id
  rescue StandardError
    blob&.purge
    raise
  end

  def read(id)
    value = Redis::Alfred.get("#{PREFIX}#{id}")
    JSON.parse(value) if value.present?
  end

  def pending?(id)
    read(id)&.dig('status') == 'pending'
  end

  # Só um job converte por vez; os outros esperam a vez (`VideoConversionJob`).
  def with_lock
    token = SecureRandom.hex(8)
    return false unless Redis::Alfred.set(LOCK_KEY, token, nx: true, ex: LOCK_TTL.to_i)

    begin
      yield
    ensure
      Redis::Alfred.delete_if_equals(LOCK_KEY, token)
    end
    true
  end

  # Reentregue pelo Sidekiq depois de um reinício (o original fica), roda de novo: subir duas vezes para a Meta não faz
  # mal. Recusa nossa ou da Meta encerra com o código que a tela traduz; erro inesperado sobe para o job.
  def perform(id)
    data = read(id)
    return unless data && data['status'] == 'pending'

    blob = ActiveStorage::Blob.find_by(id: data['blob_id'])
    return finish(id, 'status' => 'failed', 'error' => 'video_unreadable') unless blob

    begin
      finish(id, 'status' => 'done', 'result' => convert_and_store(data, blob))
    rescue *KNOWN_FAILURES => e
      finish(id, 'status' => 'failed', 'error' => failure_code(e))
    end
    discard(blob)
  rescue StandardError
    discard(blob)
    raise
  end

  # Os mesmos textos do pedido síncrono (`WhatsappTemplatesController#refused`, `#meta_refused`, `#meta_unreachable`).
  def failure_code(error)
    case error
    when Whatsapp::Templates::Manager::Refused then error.code
    when Whatsapp::Templates::MetaClient::MetaError then error.own_text ? error.code : 'meta_text'
    when Whatsapp::Templates::MetaClient::Unsupported then 'inbox_not_supported'
    else 'meta_unreachable'
    end
  end

  def convert_and_store(data, blob)
    inbox = Inbox.find_by!(id: data['inbox_id'], account_id: data['account_id'])
    upload = Whatsapp::Templates::MediaUpload.new(inbox: inbox, account_user: AccountUser.find(data['account_user_id']))
    blob.open do |file|
      Whatsapp::Templates::VideoForMeta.open_converted(file.path, blob.filename.to_s) { |media| upload.store(media) }
    end
  end

  # O resultado já gravado vale: falha ao apagar o original fica para a limpeza agendada.
  def discard(blob)
    blob&.purge
  rescue StandardError => e
    Rails.logger.warn("[whatsapp_templates][video_conversion] original #{blob.id} não apagado: #{e.class.name}")
  end

  # Só o pedido ainda pendente muda: `done` não vira `failed` depois. KEEPTTL: não ressuscita um pedido expirado.
  def finish(id, changes)
    data = read(id)
    return unless data && data['status'] == 'pending'

    Redis::Alfred.with { |conn| conn.set("#{PREFIX}#{id}", data.merge(changes).to_json, xx: true, keepttl: true) }
  end

  def write(id, data)
    Redis::Alfred.set("#{PREFIX}#{id}", data.to_json, ex: TTL.to_i)
  end
end

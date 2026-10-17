class Crm::FollowUps::MetadataSanitizer
  ALLOWED_KEYS = %w[
    message_body
    whatsapp_api_message_template_id
    template_name
    template_namespace
    template_language
    template_processed_params
    sent_message_id
    sent_at
    send_mode
    send_error
    source
    touch
  ].freeze

  # Escritas só pelo servidor (runners de IA): o cliente nunca as define (chat#1349). `memoria` (#1601): a marca da
  # tarefa de retomar o atendimento; o cliente não cria nem apaga.
  SERVER_OWNED_KEYS = %w[delivery_transport hybrid_free_form_reason memoria].freeze
  # Ficam no PATCH que troca o metadata inteiro (#1601): sem a marca, a tarefa sem prazo viraria um lembrete comum e o
  # DueProcessor passaria a vencê-la e avisar.
  KEPT_ON_UPDATE = %w[memoria].freeze

  def self.without_server_keys(metadata)
    metadata.to_h.stringify_keys.except(*SERVER_OWNED_KEYS)
  end

  # O metadata do cliente, sem as chaves do servidor, mais as que o PATCH não pode apagar.
  def self.for_update(metadata, current)
    without_server_keys(metadata).merge(current.to_h.stringify_keys.slice(*KEPT_ON_UPDATE))
  end

  # Única fonte do que conta como "modelo nativo configurado": nome E idioma, os dois presentes. Usado pelo
  # AutoSendValidator (criação) e pelo MessageSender (envio) — nome sem idioma nunca conta como configurado
  # nos dois lados, senão um aceita e o outro recusa de forma enganosa (achado da revisão em #1349).
  def self.native_template_configured?(metadata)
    metadata = metadata.to_h.stringify_keys
    metadata['template_name'].to_s.strip.present? && metadata['template_language'].to_s.strip.present?
  end

  def initialize(metadata:, automation_mode:)
    @metadata = (metadata || {}).to_h.stringify_keys
    @automation_mode = automation_mode
  end

  def perform
    return {} unless @automation_mode.to_s == 'auto_send_message'

    sanitized = @metadata.slice(*ALLOWED_KEYS)
    sanitized['whatsapp_api_message_template_id'] = sanitized['whatsapp_api_message_template_id'].presence&.to_i
    sanitized['template_processed_params'] = sanitized['template_processed_params'].to_h if sanitized.key?('template_processed_params')
    sanitized.compact
  end
end

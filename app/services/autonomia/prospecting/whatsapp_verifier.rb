class Autonomia::Prospecting::WhatsappVerifier
  Result = Struct.new(:lead, :exists, :phone, :chat_id, keyword_init: true)

  Error = Class.new(StandardError)

  # Cada número tem a sua verificação: o telefone do Google e o WhatsApp achado no site (#678).
  SOURCES = {
    google: { attribute: :phone, metadata_key: 'whatsapp_verification' },
    site: { attribute: :enriched_whatsapp, metadata_key: 'site_whatsapp_verification' }
  }.freeze

  def self.available_for?(account)
    Waha::Config.enabled? && session_for(account).present?
  end

  def self.session_for(account)
    inbox = account.inboxes.where(channel_type: 'Channel::Api').includes(:channel).find do |item|
      attrs = item.channel.additional_attributes.to_h
      attrs['provider'] == 'waha' && attrs['session'].present?
    end

    inbox&.channel&.additional_attributes.to_h['session']
  end

  def initialize(lead:, source: :google)
    @lead = lead
    @account = lead.account
    @source = SOURCES.fetch(source)
  end

  def perform
    raise Error, 'prospecting.whatsapp.phone_missing' if normalized_phone.blank?
    raise Error, 'prospecting.whatsapp.waha_not_configured' unless Waha::Config.enabled?
    raise Error, 'prospecting.whatsapp.session_missing' if waha_session.blank?

    response = Waha::Client.new.check_contact_exists(phone: normalized_phone, session: waha_session)
    exists = ActiveModel::Type::Boolean.new.cast(response['numberExists'])
    chat_id = exists ? response['chatId'].presence || "#{normalized_phone.delete('+')}#{Autonomia::Prospecting::PhoneContract::CHAT_ID_SUFFIX}" : nil

    persist_result!(exists: exists, chat_id: chat_id)

    Result.new(lead: @lead.reload, exists: exists, phone: normalized_phone, chat_id: chat_id)
  rescue Waha::Client::Error => e
    persist_failure!(e.message)
    raise Error, 'prospecting.whatsapp.verification_failed'
  end

  private

  def normalized_phone
    @normalized_phone ||= Autonomia::Prospecting::PhoneContract.e164(
      checked_number, region: Autonomia::Prospecting::PhoneContract.region_for(@account)
    )
  end

  # O número como estava no lead quando a consulta começou.
  def checked_number
    @checked_number ||= @lead.public_send(@source[:attribute])
  end

  def waha_session
    @waha_session ||= self.class.session_for(@account)
  end

  def persist_result!(exists:, chat_id:)
    persist!(
      'status' => exists ? 'verified' : 'not_whatsapp',
      'phone' => normalized_phone,
      'chat_id' => chat_id,
      'session' => waha_session,
      'checked_at' => Time.current.iso8601
    )
  end

  def persist_failure!(message)
    persist!(
      'status' => 'failed',
      'phone' => normalized_phone,
      'session' => waha_session,
      'error' => message.to_s.truncate(300),
      'checked_at' => Time.current.iso8601
    )
  end

  # Enriquecimento e verificação rodam em jobs paralelos: gravar só a chave desta verificação no jsonb, sem
  # reescrever o metadata lido antes (ENRIQ-57). E só se o lead ainda tem o número consultado: uma busca que trocou o
  # telefone no meio já deixou o lead na fila para o número novo (ENRIQ-69).
  def persist!(payload)
    same_number = Autonomia::Prospecting::Lead.where(id: @lead.id).where(@source[:attribute] => checked_number)
    same_number.update_all( # rubocop:disable Rails/SkipsModelValidations
      ['metadata = metadata || ?::jsonb, updated_at = ?', { @source[:metadata_key] => payload.compact }.to_json, Time.current]
    )
  end
end

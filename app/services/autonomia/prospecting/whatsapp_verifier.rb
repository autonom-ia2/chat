class Autonomia::Prospecting::WhatsappVerifier
  # pending: o telefone do lead mudou durante a consulta; nada foi gravado e o número novo voltou à fila (ENRIQ-69).
  Result = Struct.new(:lead, :exists, :phone, :chat_id, :pending, keyword_init: true)

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
    record_result(ActiveModel::Type::Boolean.new.cast(response['numberExists']), response['chatId'])
  rescue Waha::Client::Error => e
    return number_changed_result unless persist_failure!(e.message)

    raise Error, 'prospecting.whatsapp.verification_failed'
  end

  private

  def record_result(exists, waha_chat_id)
    chat_id = exists ? waha_chat_id.presence || "#{normalized_phone.delete('+')}#{Autonomia::Prospecting::PhoneContract::CHAT_ID_SUFFIX}" : nil
    return number_changed_result unless persist_result!(exists: exists, chat_id: chat_id)

    Result.new(lead: @lead.reload, exists: exists, phone: normalized_phone, chat_id: chat_id)
  end

  def normalized_phone
    @normalized_phone ||= Autonomia::Prospecting::PhoneContract.e164(checked_number, region: phone_region)
  end

  def phone_region
    @phone_region ||= Autonomia::Prospecting::PhoneContract.region_for(@account)
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
  # reescrever o metadata lido antes (ENRIQ-57). E só se o lead ainda tem o número consultado, comparado em E.164 sob
  # a trava da linha, para a busca não trocar o telefone entre a conferência e a gravação (ENRIQ-69). true se gravou.
  # Lead apagado durante a consulta não tem onde gravar: false, e o lote segue.
  def persist!(payload)
    Autonomia::Prospecting::Lead.transaction do
      current = Autonomia::Prospecting::Lead.lock.find_by(id: @lead.id)
      next false if current.nil?
      next false unless Autonomia::Prospecting::PhoneContract.e164(current.public_send(@source[:attribute]), region: phone_region) == normalized_phone

      Autonomia::Prospecting::Lead.where(id: @lead.id).update_all( # rubocop:disable Rails/SkipsModelValidations
        ['metadata = metadata || ?::jsonb, updated_at = ?', { @source[:metadata_key] => payload.compact }.to_json, Time.current]
      )
      true
    end
  end

  # O resultado era do número antigo. A marca "queued" da consulta antiga sai, e o telefone do Google volta à fila para
  # o número novo, em vez de ficar em "Verificando" até o ReaperJob; o after_search da busca que trocou não o
  # recoloca, porque "queued" não conta como pendente (LeadWorkQueue.google_phone_pending?).
  # Lead apagado no meio: nada a recolocar na fila, e o resultado sai sem lead.
  def number_changed_result
    requeue_google_phone! if @source == SOURCES[:google]
    Result.new(lead: Autonomia::Prospecting::Lead.find_by(id: @lead.id), exists: nil, phone: nil, chat_id: nil, pending: true)
  end

  def requeue_google_phone!
    Autonomia::Prospecting::Lead.where(id: @lead.id)
                                .where("metadata -> 'whatsapp_verification' ->> 'status' = 'queued'")
                                .update_all(["metadata = metadata - 'whatsapp_verification', updated_at = ?", Time.current]) # rubocop:disable Rails/SkipsModelValidations
    current = Autonomia::Prospecting::Lead.find_by(id: @lead.id)
    Autonomia::Prospecting::LeadWorkQueue.enqueue_whatsapp(@account, [current]) if current
  end
end

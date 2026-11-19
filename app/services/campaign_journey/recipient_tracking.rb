# Recipient bookkeeping shared by the journey senders of Chatwoot campaigns (CampaignRecipient,
# Enterprise): WhatsApp Oficial (#1005, CampaignJourney::WhatsappOneoffRecipients) and SMS (#1004,
# CampaignJourney::SmsOneoffRecipients). Included by those prepended modules; relies on the
# service's #campaign.
#
# - D2: one `queued` recipient per eligible contact before the first message (bulk insert,
#   idempotent per campaign + contact); only queued ones are walked, in batches; whatever is still
#   queued at the end (and was not accepted by the provider) becomes failed, so no one is left
#   without a status.
# - D4: once the provider accepted a message it is never marked failed: if saving `sent` fails,
#   the status is forced to sent and the error logged.
# - #3063 (item 2): out of the account's limit per customer or sending hours (Autonomia::RitmoDeEnvio::Porteiro) the
#   recipient stays `queued` with `adiado_ate`, is not failed at the end of the run and is sent later by
#   CampaignJourney::RetomarAdiadosJob (#retomar_adiados), which the sweep enqueues when the time comes. A message that
#   went out counts for the limit.
module CampaignJourney::RecipientTracking
  NOT_PROCESSED_REASON = 'Recipient was not processed'.freeze
  INSERT_BATCH_SIZE = 1000

  # Sends the recipients whose postponement is due (CampaignJourney::RetomarAdiadosJob). The campaign already ran: no
  # recipient is created. Only the recipients due when the run started are walked; whoever of them is still queued
  # and not postponed again at the end becomes failed. Those that became due during the run wait for the next sweep.
  def retomar_adiados
    inicio = Time.current
    campaign.campaign_recipients.queued.where(adiado_ate: ..inicio).includes(:contact)
            .find_each(batch_size: INSERT_BATCH_SIZE) { |recipient| retomar_destinatario(recipient) }
    fail_unprocessed_recipients(adiados_ate: inicio)
  end

  private

  # true when the recipient has to wait: it keeps `queued`, with the time it may go.
  def adiado_pelo_ritmo?(recipient, contact)
    ate = Autonomia::RitmoDeEnvio::Porteiro.quando(account: campaign.account, contact: contact)
    return false unless ate

    recipient.update!(adiado_ate: ate)
    true
  end

  def contar_no_ritmo(recipient, origem)
    Autonomia::RitmoDeEnvio::Porteiro.contar!(account: campaign.account, contact_id: recipient.contact_id, origem: origem)
  end

  # Returns the queued recipients as a lazy, batched enumerator (never the whole list in memory).
  def register_queued_recipients(contacts)
    insert_recipients(contacts, status: :queued)
    campaign.campaign_recipients.queued.includes(:contact).find_each(batch_size: INSERT_BATCH_SIZE)
  end

  # Audience channel off at send time: everyone eligible is recorded as skipped.
  def skip_all_recipients(contacts, reason)
    insert_recipients(contacts, status: :skipped, error_message: reason)
    campaign.campaign_recipients.queued.update_all(status: CampaignRecipient.statuses[:skipped], error_message: reason) # rubocop:disable Rails/SkipsModelValidations
    []
  end

  def insert_recipients(contacts, status:, error_message: nil)
    contacts.in_batches(of: INSERT_BATCH_SIZE) do |batch|
      now = Time.current
      # Ordered so recipients (and therefore sends) follow contact id order; an unordered
      # pluck let the database return ids in any order and made the send order vary.
      rows = batch.order(:id).pluck(:id).map do |contact_id|
        { account_id: campaign.account_id, campaign_id: campaign.id, contact_id: contact_id, inbox_id: campaign.inbox_id,
          status: CampaignRecipient.statuses[status], error_message: error_message, created_at: now, updated_at: now }
      end
      CampaignRecipient.insert_all(rows, unique_by: %i[campaign_id contact_id]) if rows.any? # rubocop:disable Rails/SkipsModelValidations
    end
  end

  # Whoever was postponed is not "not processed": it stays queued for the sweep, even when its time comes before the
  # run ends. The first run fails only the never-postponed; the resumption (`adiados_ate`) only the ones it walked.
  def fail_unprocessed_recipients(adiados_ate: nil)
    queued = campaign.campaign_recipients.queued
    walked = adiados_ate ? queued.where(adiado_ate: ..adiados_ate) : queued.where(adiado_ate: nil)
    walked.where.not(id: accepted_by_provider.to_a).find_each do |recipient|
      recipient.mark_failed!(message: NOT_PROCESSED_REASON)
    end
  end

  def keep_as_sent(recipient, source_id, error)
    Rails.logger.error "[CampaignJourney] campaign=#{campaign.id} recipient=#{recipient.id} accepted by provider, mark_sent! failed: #{error.class}"
    recipient.update_columns(status: CampaignRecipient.statuses[:sent], source_id: source_id, sent_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  rescue StandardError => e
    Rails.logger.error "[CampaignJourney] campaign=#{campaign.id} recipient=#{recipient.id} could not be kept as sent: #{e.class}"
  end

  def accepted_by_provider
    @accepted_by_provider ||= Set.new
  end
end

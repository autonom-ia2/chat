# Descarte tira da campanha em andamento (chat#713, decisão de 26/09). A campanha da API do WhatsApp resolve o público
# quando começa e guarda os destinatários; tirar a etiqueta do segmento não os remove. Aqui, no SegmentRefusalSyncJob que
# o descarte já enfileira, os destinatários ainda pendentes da campanha em andamento (ou pausada) que recebeu o segmento
# da lista do lead descartado (metadata campaign_segment da lista) viram cancelados com o motivo 'discarded'. Cancelado
# não é falha: a campanha não termina com falhas por isso.
#
# A regra é a da etiqueta: o contato que outro lead elegível da mesma lista ainda alcança continua na campanha. Só sai
# quem está pendente; o que já está sendo enviado ou foi enviado fica como está (o UPDATE confere o status na hora).
class Autonomia::Prospecting::DiscardedCampaignRecipients
  CAMPAIGN_TYPE = Autonomia::Prospecting::CampaignSegmentBuilder::WHATSAPP_API
  ACTIVE_CAMPAIGN_STATUSES = %i[running paused].freeze

  def initialize(account:, eligibility: nil)
    @account = account
    @eligibility = eligibility || Autonomia::Prospecting::SegmentEligibility.new(account: account, user: nil)
  end

  # leads: os que o job releu. Só o descartado sai da campanha; o recusado é pulado na hora do envio.
  def perform(leads)
    discarded = Array(leads).select(&:discarded?)
    return if discarded.empty?

    campaign_lists(discarded).each do |campaign, list|
      contact_ids = discarded_contact_ids(list, discarded)
      next if contact_ids.empty?

      cancel!(campaign, contact_ids - @eligibility.contact_ids_kept_in(list, contact_ids))
    end
  end

  private

  # [campanha, lista]: as listas dos leads cujo segmento foi posto numa campanha da API ainda em andamento.
  def campaign_lists(leads)
    lists = lists_with_campaign(leads)
    campaigns = @account.whatsapp_api_campaigns.where(status: ACTIVE_CAMPAIGN_STATUSES, id: lists.map { |list| campaign_id(list) })
                        .index_by(&:id)
    lists.filter_map do |list|
      campaign = campaigns[campaign_id(list)]
      [campaign, list] if campaign
    end
  end

  def lists_with_campaign(leads)
    list_ids = Autonomia::Prospecting::ListLead.where(account_id: @account.id, prospect_lead_id: leads.map(&:id)).select(:prospect_list_id)
    Autonomia::Prospecting::List.where(account: @account, id: list_ids)
                                .where("metadata -> 'campaign_segment' ->> 'campaign_type' = ?", CAMPAIGN_TYPE).to_a
  end

  def discarded_contact_ids(list, leads)
    in_list = list.list_leads.where(prospect_lead_id: leads.map(&:id)).pluck(:prospect_lead_id).to_set
    leads.select { |lead| in_list.include?(lead.id) }.filter_map { |lead| @eligibility.existing_contact(lead)&.id }.uniq
  end

  def cancel!(campaign, contact_ids)
    return if contact_ids.empty?

    now = Time.current
    cancelled = campaign.whatsapp_api_campaign_recipients.pending.where(contact_id: contact_ids).update_all( # rubocop:disable Rails/SkipsModelValidations
      status: WhatsappApiCampaignRecipient.statuses[:cancelled], cancelled_at: now,
      last_error_message: WhatsappApiCampaignRecipient::DISCARDED_REASON, updated_at: now
    )
    campaign.refresh_counters! if cancelled.positive?
  end

  def campaign_id(list)
    list.metadata.to_h.dig('campaign_segment', 'campaign_id').to_i
  end
end

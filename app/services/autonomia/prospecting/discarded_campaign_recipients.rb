# Descarte tira da campanha em andamento (chat#713, decisão de 26/09). A campanha da API do WhatsApp resolve o público
# quando começa e guarda os destinatários; tirar a etiqueta do segmento não os remove. Aqui, no SegmentRefusalSyncJob que
# o descarte já enfileira, depois de tirar as etiquetas, os destinatários ainda pendentes do descartado viram cancelados
# com o motivo 'discarded'. Cancelado não é falha: a campanha não termina com falhas por isso.
#
# Quais campanhas: as da API do WhatsApp em andamento (ou pausadas) cuja audiência tem a etiqueta do segmento de uma lista
# do lead descartado. É o vínculo que o AudienceResolver usou de fato; o campaign_id do metadata da lista guarda só a
# última campanha e muda quando o segmento é refeito.
#
# A regra é a da etiqueta: o contato que ainda tem alguma etiqueta da audiência da campanha continua nela (outro lead
# elegível que mantém a etiqueta do segmento, a etiqueta de outra lista na mesma campanha, uma etiqueta comum escolhida na
# campanha). Só sai quem está pendente; o que já está sendo enviado ou foi enviado fica como está (o UPDATE confere o
# status na hora).
class Autonomia::Prospecting::DiscardedCampaignRecipients
  ACTIVE_CAMPAIGN_STATUSES = %i[running paused].freeze

  def initialize(account:, eligibility: nil)
    @account = account
    @eligibility = eligibility || Autonomia::Prospecting::SegmentEligibility.new(account: account, user: nil)
  end

  # leads: os que o job releu. Só o descartado sai da campanha; o recusado é pulado na hora do envio.
  def perform(leads)
    discarded = Array(leads).select(&:discarded?)
    return if discarded.empty?

    contact_ids_by_label = discarded_contact_ids_by_segment_label(discarded)
    return if contact_ids_by_label.empty?

    active_campaigns.each do |campaign|
      label_ids = audience_label_ids(campaign)
      candidates = contact_ids_by_label.slice(*label_ids).values.flatten.uniq
      next if candidates.empty?

      cancel!(campaign, candidates - contact_ids_still_tagged(candidates, label_ids))
    end
  end

  private

  # { id da etiqueta do segmento => [ids dos contatos dos descartados que estão na lista daquele segmento] }.
  def discarded_contact_ids_by_segment_label(leads)
    contact_by_lead = contact_id_by_lead(leads)
    rows = Autonomia::Prospecting::ListLead.where(account_id: @account.id, prospect_lead_id: contact_by_lead.keys)
                                           .pluck(:prospect_list_id, :prospect_lead_id)
    label_by_list = segment_label_by_list(rows.map(&:first).uniq)
    rows.select { |list_id, _lead_id| label_by_list.key?(list_id) }
        .group_by { |list_id, _lead_id| label_by_list[list_id] }
        .transform_values { |pairs| pairs.map { |_list_id, lead_id| contact_by_lead[lead_id] }.uniq }
  end

  def contact_id_by_lead(leads)
    leads.to_h { |lead| [lead.id, @eligibility.existing_contact(lead)&.id] }.compact
  end

  # { id da lista => id da etiqueta do segmento } das listas com segmento gerado.
  def segment_label_by_list(list_ids)
    Autonomia::Prospecting::List.where(account: @account, id: list_ids).each_with_object({}) do |list, result|
      label_id = list.metadata.to_h.dig('campaign_segment', 'label_id').to_i
      result[list.id] = label_id if label_id.positive?
    end
  end

  def active_campaigns
    @account.whatsapp_api_campaigns.where(status: ACTIVE_CAMPAIGN_STATUSES).to_a
  end

  def audience_label_ids(campaign)
    Array(campaign.audience).filter_map do |item|
      item = item.to_h.stringify_keys
      item['id'].to_i if item['type'] == 'Label' && item['id'].present?
    end
  end

  # Os contatos que ainda têm alguma etiqueta da audiência (lidos depois de o SegmentRefusalSync tirar as etiquetas).
  def contact_ids_still_tagged(contact_ids, label_ids)
    titles = @account.labels.where(id: label_ids).pluck(:title)
    return [] if titles.empty?

    ActsAsTaggableOn::Tagging.joins(:tag)
                             .where(context: 'labels', taggable_type: 'Contact', taggable_id: contact_ids, tags: { name: titles })
                             .distinct.pluck(:taggable_id)
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
end

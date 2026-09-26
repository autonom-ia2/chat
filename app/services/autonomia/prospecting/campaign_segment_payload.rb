# Bloco `segment` da campanha, igual nas Listas e na seleção da busca (#680). Cada bloqueado leva o motivo.
# Lead que não é da conta aparece só pelo id pedido, sem nome nem status.
module Autonomia::Prospecting::CampaignSegmentPayload
  module_function

  def build(result, missing_lead_ids: [])
    blocked = result.blocked_leads.map { |row| blocked_lead(row) } + missing_lead_ids.map { |id| missing_lead(id) }
    {
      label: { id: result.label.id, title: result.label.title },
      campaign: campaign(result.campaign),
      eligible_count: result.eligible_leads.size,
      blocked_count: blocked.size,
      created_contacts_count: result.created_contacts_count,
      blocked_leads: blocked
    }
  end

  # A campanha igual para os dois tipos (#732, item 11): a de envio único pelo display_id, a da API do WhatsApp pelo id.
  def campaign(campaign)
    return if campaign.nil?

    if campaign.is_a?(WhatsappApiCampaign)
      { id: campaign.id, title: campaign.title, type: Autonomia::Prospecting::CampaignSegmentBuilder::WHATSAPP_API }
    else
      { id: campaign.display_id, title: campaign.title, type: Autonomia::Prospecting::CampaignSegmentBuilder::ONE_OFF }
    end
  end

  def blocked_only(blocked_leads, missing_lead_ids: [])
    blocked = blocked_leads.map { |row| blocked_lead(row) } + missing_lead_ids.map { |id| missing_lead(id) }
    { eligible_count: 0, blocked_count: blocked.size, blocked_leads: blocked }
  end

  def blocked_lead(row)
    lead = row[:lead]
    { id: lead.id, name: lead.name, status: lead.status, reason_code: row[:reason_code], reason: row[:message] }
  end

  def missing_lead(id)
    { id: id, name: nil, status: nil, reason_code: 'not_found', reason: I18n.t('autonomia.prospecting.campaign_blocked.not_found') }
  end
end

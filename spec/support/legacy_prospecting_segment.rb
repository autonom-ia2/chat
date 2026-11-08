# O segmento por etiqueta da Prospecção antiga, como ficou gravado nas contas (#2695 F3b: a criação saiu). A manutenção
# das etiquetas que já existem (SegmentRefusalSync, DiscardedCampaignRecipients, LeadsDoContatoExcluido) continua e
# trabalha sobre estes dados: a etiqueta prospeccao_<lista>_<nome> fora do menu, nos contatos dos leads elegíveis da
# lista; a lista com metadata['campaign_segment'] (label_id, label_ids, label_title, campanha); e, quando houver
# campanha, a etiqueta na audiência dela. Usado só para montar esse estado nos specs da manutenção.
module LegacyProspectingSegment
  # Devolve a etiqueta. campaign: Campaign (envio único) ou WhatsappApiCampaign.
  def legacy_prospecting_segment(list:, user:, campaign: nil, segment_name: nil)
    label = legacy_segment_label(list, segment_name || list.name)
    eligibility = Autonomia::Prospecting::SegmentEligibility.new(account: list.account, user: user)
    list.leads.order(:id).each do |lead|
      next unless eligibility.block_reason(lead).nil?

      contact = Autonomia::Prospecting::ContactConverter.new(lead: lead, user: user, consent_veto: eligibility.consent_veto).perform.contact
      contact.label_list.add(label.title)
      contact.save!
    end
    legacy_segment_campaign(campaign, label) if campaign
    legacy_segment_metadata(list, label, campaign)
    label
  end

  private

  def legacy_segment_label(list, name)
    slug = ActiveSupport::Inflector.transliterate(name.to_s).downcase.tr(' ', '_')
    list.account.labels.find_or_create_by!(title: "prospeccao_#{list.id}_#{slug}"[0, 120]) do |label|
      label.description = "Segmento gerado pela prospeccao: #{list.name}"
      label.show_on_sidebar = false
    end
  end

  def legacy_segment_campaign(campaign, label)
    audience = Array(campaign.audience).map { |item| item.to_h.stringify_keys }
    campaign.update!(audience: audience + [{ 'type' => 'Label', 'id' => label.id }])
  end

  def legacy_segment_metadata(list, label, campaign)
    metadata = list.metadata.to_h
    metadata['campaign_segment'] = {
      'label_id' => label.id, 'label_ids' => (list.segment_label_ids + [label.id]).uniq, 'label_title' => label.title,
      'campaign_id' => campaign&.id, 'campaign_type' => legacy_segment_campaign_type(campaign)
    }.compact
    list.update!(metadata: metadata)
  end

  def legacy_segment_campaign_type(campaign)
    return if campaign.nil?

    campaign.is_a?(WhatsappApiCampaign) ? 'whatsapp_api' : 'one_off'
  end
end

# Só nos specs da manutenção, marcados com :legacy_prospecting_segment.
RSpec.configure { |config| config.include LegacyProspectingSegment, :legacy_prospecting_segment }

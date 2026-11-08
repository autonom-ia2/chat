# Quem chegou pelos formulários dos anúncios (#2195): os últimos leads que viraram card, com o contato, o anúncio e o
# funil. Traz nome, telefone e e-mail: só vai à tela de quem tem `contact_view` (o controller decide), e só dos cards
# que a pessoa enxerga (acesso por funil, o mesmo do Kanban).
class Crm::MetaAds::LeadForms::RecentLeads
  LIMIT = 10

  def initialize(account, visible_cards:)
    @account = account
    @visible_cards = visible_cards
  end

  def payload
    leads = Crm::MetaAdsLead.where(account_id: @account.id, card_id: @visible_cards.select(:id))
                            .order(received_at: :desc).limit(LIMIT).includes(:contact, card: %i[pipeline stage])
    names = Crm::MetaAdsLeadForm.where(account_id: @account.id, form_id: leads.map(&:form_id)).pluck(:form_id, :form_name).to_h
    leads.map { |lead| recent_payload(lead, names[lead.form_id]) }
  end

  private

  def recent_payload(lead, form_name)
    contact = lead.contact
    card = lead.card
    {
      id: lead.id, card_id: lead.card_id, name: contact&.name, phone: contact&.phone_number, email: contact&.email,
      form_id: lead.form_id, form_name: form_name, ad_name: lead.ad_name, campaign_name: lead.campaign_name,
      received_at: lead.received_at.iso8601, new_contact: lead.new_contact
    }.merge(card_payload(card))
  end

  def card_payload(card)
    return { pipeline_id: nil, pipeline_name: nil, stage_name: nil } if card.nil?

    { pipeline_id: card.pipeline_id, pipeline_name: card.pipeline&.name, stage_name: card.stage&.name }
  end
end

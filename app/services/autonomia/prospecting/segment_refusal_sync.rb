# Recusa depois do segmento (#732): as campanhas leem o público pela etiqueta do segmento mais tarde (a de envio único no
# disparo, a da API do WhatsApp ao começar). Quando um lead é descartado ou marcado como recusado, as etiquetas de
# segmento que o contato dele já recebeu saem na hora, sem esperar alguém refazer o segmento.
#
# Entram as listas com segmento que contêm o lead e as listas cuja etiqueta está no contato que o lead alcança: a recusa
# vale para o número, não para o lead (ConsentVeto), então o lead de outra lista com o mesmo contato também sai.
# Em cada lista, a regra é a do segmento refeito (CampaignSegmentBuilder + SegmentLabelRemover): o contato que um lead
# elegível da lista ainda alcança fica com a etiqueta. Nada é etiquetado e nenhum contato é criado aqui.
class Autonomia::Prospecting::SegmentRefusalSync
  REFUSAL_STATUSES = %w[discarded no_consent].freeze

  def initialize(account:, user:)
    @account = account
    @user = user
  end

  def perform(leads)
    refused = Array(leads).select { |lead| REFUSAL_STATUSES.include?(lead.status) }
    return if refused.empty?

    with_suppressed_contact_events do
      affected_lists(refused).each { |list, label| remove_refused_labels(list, label) }
    end
  end

  private

  def affected_lists(refused)
    list_ids = Autonomia::Prospecting::ListLead.where(prospect_lead_id: refused.map(&:id)).distinct.pluck(:prospect_list_id).to_set
    contact_labels = refused.filter_map { |lead| existing_contact(lead) }.flat_map(&:label_list).to_set

    segmented_lists.select { |list, label| list_ids.include?(list.id) || contact_labels.include?(label.title) }
  end

  # [lista, etiqueta] de cada lista da conta cujo segmento foi gerado e cuja etiqueta ainda existe.
  def segmented_lists
    lists = Autonomia::Prospecting::List.where(account: @account)
                                        .where("metadata -> 'campaign_segment' ->> 'label_id' IS NOT NULL").to_a
    labels = @account.labels.where(id: lists.map { |list| segment_label_id(list) }).index_by(&:id)

    lists.filter_map do |list|
      label = labels[segment_label_id(list)]
      [list, label] if label
    end
  end

  def remove_refused_labels(list, label)
    builder = Autonomia::Prospecting::CampaignSegmentBuilder.new(list: list, user: @user)
    kept_contact_ids = builder.eligible_leads.filter_map { |lead| existing_contact(lead)&.id }
    Autonomia::Prospecting::SegmentLabelRemover.new(label: label, user: @user, kept_contact_ids: kept_contact_ids)
                                               .perform(builder.blocked_details)
  end

  def segment_label_id(list)
    list.metadata.to_h.dig('campaign_segment', 'label_id').to_i
  end

  def existing_contact(lead)
    Autonomia::Prospecting::ContactConverter.new(lead: lead, user: @user).existing_contact
  end

  # Tirar a etiqueta não é ação do contato: o mesmo silêncio do segmento (CampaignSegmentBuilder).
  def with_suppressed_contact_events
    previous = Current.suppress_contact_events
    Current.suppress_contact_events = true
    yield
  ensure
    Current.suppress_contact_events = previous
  end
end

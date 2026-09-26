# Recusa depois do segmento (#732): as campanhas leem o público pela etiqueta do segmento mais tarde (a de envio único no
# disparo, a da API do WhatsApp ao começar). Quando um lead é descartado ou marcado como recusado, a recusa gravada
# enfileira o SegmentRefusalSyncJob, e este serviço tira dos contatos que os leads recusados alcançam as etiquetas de
# segmento que eles já receberam, sem esperar alguém refazer o segmento. A resposta da recusa não depende disto.
#
# O trabalho é o dos contatos recusados, não o das listas: o pedido para parar vale para o número e o e-mail
# (ConsentVeto), então entram os contatos que ele veta e as listas cuja etiqueta está neles, estejam ou não os leads
# nelas. Em cada lista, a regra é a do segmento refeito: o contato que um lead elegível da lista ainda alcança fica com
# a etiqueta. Só os leads que podem alcançar esses contatos são avaliados, com um ConsentVeto e um contato por lead para
# a execução inteira. Nada é etiquetado e nenhum contato é criado aqui.
#
# A campanha da API do WhatsApp que já começou resolveu o público antes e guarda os destinatários pendentes; tirar a
# etiqueta não os remove. Quem recusou é pulado na hora do envio (DeliveryEngine confere a recusa do contato); o
# descartado sai dos pendentes aqui mesmo, pelo DiscardedCampaignRecipients.
class Autonomia::Prospecting::SegmentRefusalSync
  # Chamado depois de a recusa estar gravada: só enfileira quem de fato ficou descartado ou recusado.
  def self.enqueue(account:, leads:)
    lead_ids = Array(leads).select { |lead| refused?(lead) }.map(&:id).sort
    return if lead_ids.empty?

    Autonomia::Prospecting::SegmentRefusalSyncJob.perform_later(account.id, lead_ids)
  end

  def self.refused?(lead)
    lead.discarded? || lead.consent_refused?
  end

  def initialize(account:)
    @account = account
    @eligibility = Autonomia::Prospecting::SegmentEligibility.new(account: account, user: nil)
  end

  # O status e a recusa são relidos: o lead que voltou atrás antes do job não perde a etiqueta nem sai da campanha.
  def perform(lead_ids)
    leads = refused_leads(lead_ids)
    remove_labels(leads)
    Autonomia::Prospecting::DiscardedCampaignRecipients.new(account: @account, eligibility: @eligibility).perform(leads)
  end

  private

  def remove_labels(leads)
    reached = leads.flat_map { |lead| refused_contacts(lead).map { |contact| [lead, contact] } }
    return if reached.empty?

    tagged_lists(reached.map(&:last)).each do |list, label, tagged_contact_ids|
      targets = reached.select { |_lead, contact| tagged_contact_ids.include?(contact.id) }
      remove_label(list, label, targets)
    end
  end

  # O descartado tira só o próprio contato. O pedido para parar vale para o número e o e-mail (ConsentVeto): sai de todo
  # contato da conta que ele veta, mesmo que seja o de outro lead, como a unidade com o WhatsApp que a matriz recusou.
  def refused_contacts(lead)
    own = @eligibility.existing_contact(lead)
    contacts = lead.consent_refused? ? [own, *@eligibility.consent_veto.contacts_vetoed_by(lead)] : [own]
    contacts.compact.uniq(&:id)
  end

  def refused_leads(lead_ids)
    leads = Autonomia::Prospecting::Lead.where(account: @account, id: Array(lead_ids))
    leads.discarded.or(leads.consent_refused).includes(:contact).order(:id).to_a
  end

  # [lista, etiqueta, ids dos contatos recusados que têm a etiqueta] das listas com segmento gerado.
  def tagged_lists(contacts)
    lists = segmented_lists
    return [] if lists.empty?

    tagged = segment_taggings(contacts.map(&:id), lists.map { |_list, label| label.title })
    lists.filter_map do |list, label|
      contact_ids = tagged[label.title]
      [list, label, contact_ids.to_set] if contact_ids.present?
    end
  end

  # [lista, etiqueta] para cada etiqueta que o segmento de cada lista já gerou (List#segment_label_ids): a campanha que
  # começou com a etiqueta antiga de um segmento refeito com outro nome ainda a tem na audiência.
  def segmented_lists
    lists = Autonomia::Prospecting::List.where(account: @account)
                                        .where("metadata -> 'campaign_segment' ->> 'label_id' IS NOT NULL").to_a
    labels = @account.labels.where(id: lists.flat_map(&:segment_label_ids)).index_by(&:id)

    lists.flat_map do |list|
      list.segment_label_ids.filter_map { |label_id| [list, labels[label_id]] if labels[label_id] }
    end
  end

  # { título da etiqueta => [ids dos contatos] }, numa consulta.
  def segment_taggings(contact_ids, titles)
    ActsAsTaggableOn::Tagging.joins(:tag)
                             .where(context: 'labels', taggable_type: 'Contact', taggable_id: contact_ids, tags: { name: titles })
                             .pluck('tags.name', :taggable_id)
                             .group_by(&:first).transform_values { |rows| rows.map(&:last) }
  end

  def remove_label(list, label, targets)
    kept = @eligibility.contact_ids_kept_in(list, targets.to_set { |_lead, contact| contact.id })
    remover = Autonomia::Prospecting::SegmentLabelRemover.new(label: label, user: nil, kept_contact_ids: kept)
    targets.each { |lead, contact| remover.remove(lead: lead, contact: contact) }
  end
end

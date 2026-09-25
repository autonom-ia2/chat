# Recusa depois do segmento (#732): as campanhas leem o público pela etiqueta do segmento mais tarde (a de envio único no
# disparo, a da API do WhatsApp ao começar). Quando um lead é descartado ou marcado como recusado, a recusa gravada
# enfileira o SegmentRefusalSyncJob, e este serviço tira dos contatos que os leads recusados alcançam as etiquetas de
# segmento que eles já receberam, sem esperar alguém refazer o segmento. A resposta da recusa não depende disto.
#
# O trabalho é o dos contatos recusados, não o das listas: a recusa vale para o número (ConsentVeto), então entram as
# listas cuja etiqueta está nesses contatos, estejam ou não os leads nelas. Em cada lista, a regra é a do segmento
# refeito: o contato que um lead elegível da lista ainda alcança fica com a etiqueta. Só os leads que podem alcançar
# esses contatos são avaliados, com um ConsentVeto e um contato por lead para a execução inteira. Nada é etiquetado e
# nenhum contato é criado aqui.
#
# Limitação conhecida: a campanha da API do WhatsApp que já começou resolveu o público antes e guarda os destinatários
# pendentes; tirar a etiqueta não os remove. Isso é do núcleo de campanhas (AudienceResolver/DeliveryEngine), fora daqui.
class Autonomia::Prospecting::SegmentRefusalSync
  REFUSAL_STATUSES = %w[discarded no_consent].freeze

  # Chamado depois de a recusa estar gravada: só enfileira quem de fato ficou recusado.
  def self.enqueue(account:, leads:)
    lead_ids = Array(leads).select { |lead| REFUSAL_STATUSES.include?(lead.status) }.map(&:id).sort
    return if lead_ids.empty?

    Autonomia::Prospecting::SegmentRefusalSyncJob.perform_later(account.id, lead_ids)
  end

  def initialize(account:)
    @account = account
    @eligibility = Autonomia::Prospecting::SegmentEligibility.new(account: account, user: nil)
  end

  # O status é relido: o lead que voltou atrás antes do job não perde a etiqueta.
  def perform(lead_ids)
    reached = refused_leads(lead_ids).filter_map do |lead|
      contact = @eligibility.existing_contact(lead)
      [lead, contact] if contact
    end
    return if reached.empty?

    tagged_lists(reached.map(&:last)).each do |list, label, tagged_contact_ids|
      targets = reached.select { |_lead, contact| tagged_contact_ids.include?(contact.id) }
      remove_label(list, label, targets)
    end
  end

  private

  def refused_leads(lead_ids)
    Autonomia::Prospecting::Lead.where(account: @account, id: Array(lead_ids), status: REFUSAL_STATUSES)
                                .includes(:contact).order(:id).to_a
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

  def segmented_lists
    lists = Autonomia::Prospecting::List.where(account: @account)
                                        .where("metadata -> 'campaign_segment' ->> 'label_id' IS NOT NULL").to_a
    labels = @account.labels.where(id: lists.map { |list| segment_label_id(list) }).index_by(&:id)

    lists.filter_map do |list|
      label = labels[segment_label_id(list)]
      [list, label] if label
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
    kept = kept_contact_ids(list, targets.to_set { |_lead, contact| contact.id })
    remover = Autonomia::Prospecting::SegmentLabelRemover.new(label: label, user: nil, kept_contact_ids: kept)
    targets.each { |lead, contact| remover.remove(lead: lead, contact: contact) }
  end

  # Dos contatos recusados, os que um lead elegível da lista ainda alcança. Só entram na conta os leads ligados a um
  # desses contatos e os sem contato que estão prontos (que acham o contato pelo telefone, identificador ou e-mail).
  def kept_contact_ids(list, target_ids)
    list.leads.includes(:contact).to_a.filter_map do |lead|
      next unless may_reach?(lead, target_ids)

      contact_id = @eligibility.existing_contact(lead)&.id
      contact_id if target_ids.include?(contact_id) && @eligibility.block_reason(lead).nil?
    end
  end

  # Sem consulta: o lead ligado a outro contato não alcança os recusados, e o que não está pronto não é elegível.
  def may_reach?(lead, target_ids)
    (lead.contact.nil? || target_ids.include?(lead.contact_id)) && @eligibility.lead_ready?(lead)
  end

  def segment_label_id(list)
    list.metadata.to_h.dig('campaign_segment', 'label_id').to_i
  end
end

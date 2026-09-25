# A etiqueta do segmento tem nome estável (prospeccao_<lista>_<nome>) e a campanha lê o público por ela: na hora do envio
# (envio único) ou ao começar (API do WhatsApp). Quem foi etiquetado antes e depois recusou, foi bloqueado ou teve o lead
# descartado perde a etiqueta quando o segmento é refeito e também depois da recusa (SegmentRefusalSync), senão
# receberia a mensagem mesmo aparecendo como "fica fora" (#732). O contato que um lead elegível da lista também alcança
# fica com a etiqueta.
#
# Sai só a ligação da etiqueta com o contato (a tagging), como em Labels::DestroyService: o contato não guarda cópia das
# etiquetas, e salvar o contato inteiro por causa dela faria um e-mail ou telefone antigo que o Contact hoje recusa
# impedir a remoção. A falha de um contato vai para o registro e não para os outros.
class Autonomia::Prospecting::SegmentLabelRemover
  # O que a pessoa decidiu. Falta de telefone, de WhatsApp ou de status não tira a etiqueta.
  REFUSAL_REASONS = %w[discarded opt_out contact_blocked].freeze

  def initialize(label:, user:, kept_contact_ids:)
    @label = label
    @user = user
    @kept_contact_ids = kept_contact_ids.to_set
  end

  # blocked_details: as linhas do CampaignSegmentBuilder ({ lead:, reason_code: }).
  def perform(blocked_details)
    blocked_details.each do |row|
      next unless REFUSAL_REASONS.include?(row[:reason_code])

      remove(lead: row[:lead], contact: Autonomia::Prospecting::ContactConverter.new(lead: row[:lead], user: @user).existing_contact)
    end
  end

  # Tira a etiqueta do contato que o lead recusado alcança, a não ser que um lead elegível também o alcance. O savepoint
  # deixa a transação do segmento seguir quando um contato falha.
  def remove(lead:, contact:)
    return if contact.nil? || @kept_contact_ids.include?(contact.id)

    ActiveRecord::Base.transaction(requires_new: true) { label_taggings(contact).delete_all }
  rescue StandardError => e
    Autonomia::Prospecting::EventLog.emit('segment.label_removal_failed', lead: lead, reason: e, level: :warn)
    ChatwootExceptionTracker.new(e, account: lead.account).capture_exception
  end

  private

  def label_taggings(contact)
    ActsAsTaggableOn::Tagging.where(
      context: 'labels', taggable_type: 'Contact', taggable_id: contact.id,
      tag_id: ActsAsTaggableOn::Tag.where(name: @label.title).select(:id)
    )
  end
end

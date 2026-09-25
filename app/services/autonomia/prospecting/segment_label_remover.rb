# A etiqueta do segmento tem nome estável (prospeccao_<lista>_<nome>) e a campanha lê o público por ela: na hora do envio
# (envio único) ou ao começar (API do WhatsApp). Quem foi etiquetado antes e depois recusou, foi bloqueado ou teve o lead
# descartado perde a etiqueta quando o segmento é refeito, senão receberia a mensagem mesmo aparecendo como "fica fora"
# (#732). O contato que um lead elegível da lista também alcança fica com a etiqueta.
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

      remove_from(Autonomia::Prospecting::ContactConverter.new(lead: row[:lead], user: @user).existing_contact)
    end
  end

  private

  def remove_from(contact)
    return if contact.nil? || @kept_contact_ids.include?(contact.id)
    return unless contact.label_list.include?(@label.title)

    contact.label_list.remove(@label.title)
    contact.save!
  end
end

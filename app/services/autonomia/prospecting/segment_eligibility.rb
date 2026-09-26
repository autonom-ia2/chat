# Quem entra no segmento de campanha da Prospecção e, se não entra, por quê (#680, ACAO-26/27). As regras valem para o
# lead na conta, não para a lista: o CampaignSegmentBuilder pergunta por todos os leads da lista, e a recusa depois do
# segmento (SegmentRefusalSync) só pelos poucos que alcançam os contatos recusados, com um ConsentVeto e um contato por
# lead para a execução inteira.
class Autonomia::Prospecting::SegmentEligibility
  ELIGIBLE_STATUS = 'ready_for_campaign'.freeze

  def initialize(account:, user:)
    @account = account
    @user = user
    @contacts = {}
  end

  # A ordem é a da explicação mais útil: primeiro o que a pessoa decidiu (descarte, pedido para parar, bloqueio),
  # depois o que falta no lead. Contato bloqueado ou que pediu para parar nunca recebe a etiqueta.
  # A recusa de outro lead com o mesmo contato, telefone ou e-mail também vale (ConsentVeto).
  def block_reason(lead)
    return 'discarded' if lead.discarded?
    return 'opt_out' if lead.consent_refused?

    contact = existing_contact(lead)
    return 'opt_out' if consent_veto.vetoed?(lead: lead, contact: contact)

    contact_block_reason(contact) || lead_block_reason(lead)
  end

  # O que o próprio lead decide, sem consultar contato: não recusou, tem telefone, WhatsApp verificado e está pronto.
  def lead_ready?(lead)
    !lead.discarded? && !lead.consent_refused? && lead_block_reason(lead).nil?
  end

  # O mesmo contato que o ContactConverter vai etiquetar: o do lead ou o que ele acha pelo WhatsApp verificado, pelo
  # telefone, pelo identificador ou pelo e-mail. Uma consulta por lead.
  def existing_contact(lead)
    return @contacts[lead.id] if @contacts.key?(lead.id)

    @contacts[lead.id] = Autonomia::Prospecting::ContactConverter.new(lead: lead, user: @user).existing_contact
  end

  # Dos contatos (target_ids), os que um lead elegível da lista ainda alcança: esses ficam com a etiqueta do segmento e na
  # campanha. Só entram na conta os leads ligados a um desses contatos e os sem contato que estão prontos (que acham o
  # contato pelo telefone, identificador ou e-mail).
  def contact_ids_kept_in(list, target_ids)
    target_ids = target_ids.to_set
    list.leads.includes(:contact).to_a.filter_map do |lead|
      next unless may_reach?(lead, target_ids)

      contact_id = existing_contact(lead)&.id
      contact_id if target_ids.include?(contact_id) && block_reason(lead).nil?
    end
  end

  # Um só para a execução: a recusa depois do segmento usa o mesmo para achar os contatos vetados.
  def consent_veto
    @consent_veto ||= Autonomia::Prospecting::ConsentVeto.new(account: @account)
  end

  private

  # Sem consulta: o lead ligado a outro contato não alcança os alvos, e o que não está pronto não é elegível.
  def may_reach?(lead, target_ids)
    (lead.contact.nil? || target_ids.include?(lead.contact_id)) && lead_ready?(lead)
  end

  def contact_block_reason(contact)
    return if contact.nil?
    return 'contact_blocked' if contact.blocked?

    'opt_out' if contact.opted_out? || card_opted_out?(contact)
  end

  def lead_block_reason(lead)
    return 'no_phone' if lead.phone.blank?
    return 'no_whatsapp' unless whatsapp_verified?(lead)

    'not_ready' unless lead.status == ELIGIBLE_STATUS
  end

  # A recusa gravada no contato (chat#713) vale de qualquer origem. Quem respondeu "parar" ao follow-up da IA ainda fica
  # marcado só no card (Crm::FollowUps::AutoFollowupCanceler).
  def card_opted_out?(contact)
    @account.crm_cards.where(contact_id: contact.id)
            .exists?(["metadata->'ai'->'auto_followup_state'->>'opted_out' = 'true'"])
  end

  def whatsapp_verified?(lead)
    lead.metadata.to_h.dig('whatsapp_verification', 'status') == 'verified'
  end
end

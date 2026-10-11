# O pedido de parar no follow-up de IA (#1317) fica marcado no card (`auto_followup_state.opted_out`). Essa marca é a
# prova da recusa 'follow_up_reply' (#1325): enquanto algum card marcado apontar para a pessoa, a recusa vale.
#
# - contact_for: o contato de um card, na mesma ordem do follow-up de IA. O planner cria o toque na conversa primária do
#   card, e o runner (AutoFollowupRunner#followup_contact) pergunta pelo contato dessa conversa; sem conversa, o do card.
# - No "sim", o card guarda qual contato foi marcado (CONTACT_KEY). É esse contato que a marca prova e que o reset libera,
#   mesmo que depois o card seja ligado a outro contato ou perca a conversa. Card marcado antes da chave usa contact_for.
# - same_person: como as outras recusas (Contacts::OptOutInheritance), a recusa é da pessoa do número ou do e-mail: os
#   contatos da mesma conta com o mesmo telefone ou e-mail. person_marked? vale para qualquer um deles.
# - transfer_marks!: na fusão de contatos, as marcas do contato absorvido passam para o que fica.
class Crm::FollowUps::CardOptOut
  CONTACT_KEY = 'opt_out_contact_id'.freeze
  STATE_SQL = "crm_cards.metadata->'ai'->'auto_followup_state'".freeze
  OPTED_OUT_SQL = "#{STATE_SQL}->>'opted_out' = 'true'".freeze
  MARKED_CONTACT_SQL = "#{STATE_SQL}->>'#{CONTACT_KEY}'".freeze

  class << self
    def contact_for(card)
      card.primary_conversation&.contact || card.contact
    end

    # A mesma regra do OPTED_OUT_SQL ('true' exato), para a prova em Ruby e em SQL concordarem. O planner
    # (AutoFollowupPlanner#opted_out?) aceita mais formas de verdadeiro de propósito: lá, na dúvida, não re-arma.
    def card_opted_out?(card)
      state(card)['opted_out'].to_s == 'true'
    end

    # O contato que a marca do card prova: o gravado no "sim" ou, em card antigo, o de contact_for.
    def marked_contact(card)
      contact_id = state(card)[CONTACT_KEY]
      return contact_for(card) if contact_id.blank?

      Contact.find_by(id: contact_id, account_id: card.account_id)
    end

    # O próprio contato e os da mesma conta com o mesmo telefone ou e-mail. Telefone e e-mail em branco não juntam ninguém.
    def same_person(contact)
      contacts = Contact.where(account_id: contact.account_id)
      scope = contacts.where(id: contact.id)
      scope = scope.or(contacts.where(phone_number: contact.phone_number)) if contact.phone_number.present?
      scope = scope.or(contacts.where('LOWER(contacts.email) = ?', contact.email.downcase)) if contact.email.present?
      scope
    end

    # Os cards marcados da conta cuja marca aponta para um dos contatos (pela chave do "sim" ou, em card antigo, pela
    # mesma ordem de contact_for).
    def marked_cards_for(account_id:, contact_ids:)
      ids = Array(contact_ids)
      marked = Crm::Card.where(account_id: account_id).where(OPTED_OUT_SQL)
      by_marker = marked.where("#{MARKED_CONTACT_SQL} IN (?)", ids.map(&:to_s))
      legacy = marked.where("#{MARKED_CONTACT_SQL} IS NULL")
      by_conversation = legacy.where(conversation_id: Conversation.where(contact_id: ids).select(:id))
      by_contact = legacy.where(conversation_id: nil, contact_id: ids)
      by_marker.or(by_conversation).or(by_contact)
    end

    def contact_marked?(contact)
      marked_cards_for(account_id: contact.account_id, contact_ids: [contact.id]).exists?
    end

    def person_marked?(contact)
      marked_cards_for(account_id: contact.account_id, contact_ids: same_person(contact).pluck(:id)).exists?
    end

    def transfer_marks!(account:, from:, to:)
      Crm::Card.where(account_id: account.id).where("#{MARKED_CONTACT_SQL} = ?", from.id.to_s).update_all( # rubocop:disable Rails/SkipsModelValidations
        ["metadata = jsonb_set(metadata, '{ai,auto_followup_state,#{CONTACT_KEY}}', to_jsonb(?::bigint))", to.id]
      )
    end

    private

    def state(card)
      card.metadata.to_h.dig('ai', 'auto_followup_state').to_h
    end
  end
end

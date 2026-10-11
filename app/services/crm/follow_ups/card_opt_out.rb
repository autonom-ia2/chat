# O pedido de parar no follow-up de IA (#1317) fica marcado no card (`auto_followup_state.opted_out`). Essa marca é a
# prova da recusa 'follow_up_reply' do contato (#1325): enquanto algum card marcado apontar para o contato, a recusa vale.
#
# - contact_for: o contato de um card, na mesma ordem do follow-up de IA. O planner cria o toque na conversa primária do
#   card, e o runner (AutoFollowupRunner#followup_contact) pergunta pelo contato dessa conversa; sem conversa, o do card.
# - No "sim", o card guarda qual contato foi marcado (CONTACT_KEY). É esse contato que a marca prova e que o reset libera,
#   mesmo que depois o card seja ligado a outro contato ou perca a conversa. Card marcado antes da chave usa contact_for.
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

    def marked_cards_for(contact)
      marked = Crm::Card.where(account_id: contact.account_id).where(OPTED_OUT_SQL)
      by_marker = marked.where("#{MARKED_CONTACT_SQL} = ?", contact.id.to_s)
      legacy = marked.where("#{MARKED_CONTACT_SQL} IS NULL")
      by_conversation = legacy.where(conversation_id: Conversation.where(contact_id: contact.id).select(:id))
      by_contact = legacy.where(conversation_id: nil, contact_id: contact.id)
      by_marker.or(by_conversation).or(by_contact)
    end

    def contact_marked?(contact)
      marked_cards_for(contact).exists?
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

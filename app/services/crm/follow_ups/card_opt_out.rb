# O pedido de parar no follow-up de IA (#1317) fica marcado no card (`auto_followup_state.opted_out`). Essa marca é a
# prova da recusa 'follow_up_reply' do contato (#1325): enquanto algum card do contato estiver marcado, a recusa vale.
#
# - contact_for: o contato de um card, na mesma ordem do follow-up de IA. O planner cria o toque na conversa primária do
#   card, e o runner (AutoFollowupRunner#followup_contact) pergunta pelo contato dessa conversa; sem conversa, o do card.
#   O "sim" do modelo marca, o reset do drawer libera e a herança consulta sempre por aqui.
# - marked_cards_for: os cards da conta cujo contato (pela mesma ordem) é o informado e que estão marcados.
class Crm::FollowUps::CardOptOut
  OPTED_OUT_SQL = "crm_cards.metadata->'ai'->'auto_followup_state'->>'opted_out' = 'true'".freeze

  def self.contact_for(card)
    card.primary_conversation&.contact || card.contact
  end

  def self.card_opted_out?(card)
    card.metadata.to_h.dig('ai', 'auto_followup_state', 'opted_out').to_s == 'true'
  end

  def self.marked_cards_for(contact)
    marked = Crm::Card.where(account_id: contact.account_id).where(OPTED_OUT_SQL)
    by_conversation = marked.where(conversation_id: Conversation.where(contact_id: contact.id).select(:id))
    by_contact = marked.where(conversation_id: nil, contact_id: contact.id)
    by_conversation.or(by_contact)
  end

  def self.contact_marked?(contact)
    marked_cards_for(contact).exists?
  end
end

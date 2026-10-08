# Cards de uma conversa (#1141). Uma conversa pode ter vários cards — a principal de cada um ou vinculada depois — e
# quem precisa de um só pede o assunto atual (#find), nunca "o primeiro que aparecer".
#
# Ordem: o vínculo com o focused_at mais recente primeiro (assunto atual); sem foco marcado, o card cuja conversa
# principal é esta, depois o de menor id — a mesma escolha de antes, então conversa com um card só não muda nada.
# Arquivados ficam de fora; ganhos e perdidos continuam, como sempre.
class Crm::Cards::ConversationCardFinder
  def initialize(account:)
    @account = account
  end

  def find(conversation)
    all(conversation).includes(:contact, :owner, :inbox, :stage, :pipeline, :primary_conversation).first
  end

  def all(conversation)
    conversation_id = conversation.id
    linked_ids = Crm::CardConversation.where(account_id: @account.id, conversation_id: conversation_id).select(:card_id)

    active_cards.where(conversation_id: conversation_id)
                .or(active_cards.where(id: linked_ids))
                .joins(focus_join(conversation_id))
                .order(Arel.sql('crm_focus.focused_at DESC NULLS LAST'))
                .order(Arel.sql(primary_first_order(conversation_id)))
                .order(:id)
  end

  private

  def active_cards
    @account.crm_cards.where.not(status: ::Crm::Card.statuses[:archived])
  end

  def focus_join(conversation_id)
    ActiveRecord::Base.sanitize_sql_array(
      [
        'LEFT JOIN crm_card_conversations crm_focus ON crm_focus.card_id = crm_cards.id ' \
        'AND crm_focus.account_id = crm_cards.account_id AND crm_focus.conversation_id = ?',
        conversation_id
      ]
    )
  end

  def primary_first_order(conversation_id)
    ActiveRecord::Base.sanitize_sql_array(['(crm_cards.conversation_id = ?) IS TRUE DESC', conversation_id])
  end
end

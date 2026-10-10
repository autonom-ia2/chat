# Cards de uma conversa (#1141). Uma conversa pode ter vários cards — a principal de cada um ou vinculada depois — e
# quem precisa de um só pede o assunto atual (#find), nunca "o primeiro que aparecer".
#
# Ordem: cards abertos antes dos encerrados (#1143: o assunto atual é sempre um assunto em andamento); entre eles, o
# vínculo com o focused_at mais recente (assunto atual); sem foco marcado, o card cuja conversa principal é esta, depois
# o de menor id. Conversa com um card só não muda nada. Arquivados ficam de fora; ganhos e perdidos continuam.
class Crm::Cards::ConversationCardFinder
  OPEN_FIRST = "(crm_cards.status = #{::Crm::Card.statuses[:open]}) DESC".freeze
  LISTED_FOCUS_JOIN = 'LEFT JOIN crm_card_conversations crm_focus ON crm_focus.card_id = crm_cards.id ' \
                      'AND crm_focus.account_id = crm_cards.account_id AND crm_focus.conversation_id = listed.conversation_id'.freeze

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
                .order(Arel.sql(OPEN_FIRST))
                .order(Arel.sql('crm_focus.focused_at DESC NULLS LAST'))
                .order(Arel.sql(primary_first_order(conversation_id)))
                .order(:id)
  end

  # Os cards de várias conversas numa consulta só (selo da lista, #1197): a mesma regra e a mesma ordem de #all, uma
  # linha por par card/conversa, com a conversa em `listed_conversation_id`. Um card vinculado a duas conversas da
  # lista aparece nas duas.
  def all_for(conversation_ids)
    active_cards.joins(listed_join(conversation_ids))
                .joins(LISTED_FOCUS_JOIN)
                .select('crm_cards.*, listed.conversation_id AS listed_conversation_id')
                .order(Arel.sql('listed.conversation_id'))
                .order(Arel.sql(OPEN_FIRST))
                .order(Arel.sql('crm_focus.focused_at DESC NULLS LAST'))
                .order(Arel.sql('(crm_cards.conversation_id = listed.conversation_id) IS TRUE DESC'))
                .order(:id)
  end

  private

  # Pares card/conversa: a conversa principal do card ou um vínculo em crm_card_conversations.
  def listed_join(conversation_ids)
    ActiveRecord::Base.sanitize_sql_array(
      [
        'INNER JOIN (SELECT id AS card_id, conversation_id FROM crm_cards WHERE account_id = :account AND conversation_id IN (:ids) ' \
        'UNION SELECT card_id, conversation_id FROM crm_card_conversations WHERE account_id = :account AND conversation_id IN (:ids)) ' \
        'listed ON listed.card_id = crm_cards.id',
        { account: @account.id, ids: conversation_ids }
      ]
    )
  end

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

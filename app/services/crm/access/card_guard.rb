# Quem pode pôr um card num funil (#1148, parte C). O funil dos cards decide quem vê a conversa, então mover, gravar ou
# criar card num funil pode abrir a conversa para um funil inteiro. Para quem tem acesso restrito:
# - mover/gravar: a pessoa precisa ver TODAS as conversas do card (a principal e as vinculadas, de qualquer caixa) e ter
#   o funil de destino em TODAS as caixas restritas envolvidas (a do card e as das conversas). Ser só dona do card não
#   basta (senão moveria o card para o próprio funil e ganharia a conversa).
# - criar com conversa: o funil precisa ser dela na caixa da conversa e na do card.
# Sem linha de acesso, tudo liberado como hoje.
class Crm::Access::CardGuard
  def initialize(user:, account:, account_user: nil)
    @scope = Crm::Access::ConversationScope.new(user: user, account: account, account_user: account_user)
    @card_scope = Crm::Access::CardScope.new(user: user, account: account, account_user: account_user)
  end

  def move_allowed?(card, pipeline_id)
    return true unless @scope.restricted?

    conversations = card_conversations(card)
    return false unless conversations.all? { |conversation| @scope.allows?(conversation) }

    pipeline_allowed_in?([card.inbox_id] + conversations.map(&:inbox_id), pipeline_id)
  end

  def create_allowed?(pipeline_id, conversation:, inbox_id: nil)
    return true unless @scope.restricted?

    pipeline_allowed_in?([inbox_id, conversation&.inbox_id], pipeline_id)
  end

  private

  def pipeline_allowed_in?(inbox_ids, pipeline_id)
    inbox_ids.compact.uniq.all? { |inbox_id| @card_scope.pipeline_allowed?(inbox_id, pipeline_id) }
  end

  def card_conversations(card)
    ids = [card.conversation_id] + card.card_conversations.pluck(:conversation_id)
    Conversation.where(id: ids.compact.uniq).to_a
  end
end

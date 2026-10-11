# Quem pode pôr um card num funil (#1148, parte C). O funil dos cards decide quem vê a conversa, então mover, gravar ou
# criar card num funil pode abrir a conversa para um funil inteiro. Para quem tem acesso restrito:
# - mover/gravar: a pessoa precisa ver TODAS as conversas do card (a principal e as vinculadas, de qualquer caixa) e ter
#   o funil de destino em TODAS as caixas restritas envolvidas (a do card e as das conversas). Ser só dona do card não
#   basta (senão moveria o card para o próprio funil e ganharia a conversa).
# - criar com conversa: o funil precisa ser dela na caixa da conversa e na do card.
# - dono (decisão a, 11/10): só vira dono quem tem o funil do card; administrador escolhe qualquer pessoa.
# Sem linha de acesso, tudo liberado como hoje.
class Crm::Access::CardGuard
  # Dono escolhido sem o funil do card (decisão a): o controller responde 422 com o código abaixo.
  class OwnerWithoutFunnel < StandardError
    CODE = 'crm.owner_without_funnel'.freeze
  end

  def initialize(user:, account:, account_user: nil)
    @user = user
    @account = account
    @account_user = account_user
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

  # Dono do card (#1148, decisão do Rodrigo em 11/10): só vira dono quem tem o funil do card na caixa dele; o
  # administrador escolhe qualquer pessoa. Sem acesso por funil na conta, ninguém é barrado.
  def owner_allowed?(owner_id, inbox_id:, pipeline_id:)
    return true if owner_id.blank? || inbox_id.blank? || pipeline_id.blank?
    return true unless Crm::Access::AccountFlag.any?(@account.id)
    return true if administrator?

    owner = @account.users.find_by(id: owner_id)
    owner.nil? || Crm::Access::CardScope.new(user: owner, account: @account).pipeline_allowed?(inbox_id, pipeline_id)
  end

  def ensure_owner_allowed!(owner_id, inbox_id:, pipeline_id:)
    raise OwnerWithoutFunnel, OwnerWithoutFunnel::CODE unless owner_allowed?(owner_id, inbox_id: inbox_id, pipeline_id: pipeline_id)
  end

  private

  def administrator?
    (@account_user || AccountUser.find_by(account_id: @account.id, user_id: @user&.id))&.administrator?
  end

  def pipeline_allowed_in?(inbox_ids, pipeline_id)
    inbox_ids.compact.uniq.all? { |inbox_id| @card_scope.pipeline_allowed?(inbox_id, pipeline_id) }
  end

  def card_conversations(card)
    ids = [card.conversation_id] + card.card_conversations.pluck(:conversation_id)
    Conversation.where(id: ids.compact.uniq).to_a
  end
end

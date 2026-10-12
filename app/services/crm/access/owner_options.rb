# Quem NÃO pode ser dono do card (#1148, decisão a; #1149): para a tela não oferecer quem o servidor recusaria. Mesma
# regra do CardGuard#owner_allowed?, perguntada só a quem tem linha de acesso na caixa (sem linha, a pessoa pode).
# Sem acesso por funil na conta, ou se quem escolhe é administrador ou integração, ninguém é barrado.
class Crm::Access::OwnerOptions
  MAX_CARDS = 200

  def initialize(user:, account:, account_user: nil)
    @account = account
    @guard = Crm::Access::CardGuard.new(user: user, account: account, account_user: account_user)
    @blocked = {}
  end

  def blocked(inbox_id, pipeline_id)
    return [] if inbox_id.blank? || pipeline_id.blank?
    return [] unless Crm::Access::AccountFlag.any?(@account.id)

    blocked_for_pair(inbox_id, pipeline_id)
  end

  # Card novo: só responde a quem pode criar card naquele funil e caixa. Assim ninguém consulta a configuração de
  # funil dos colegas em caixas e funis que não são dele.
  def blocked_for_new_card(inbox_id, pipeline_id)
    return [] if inbox_id.blank? || pipeline_id.blank?
    return [] unless @guard.create_allowed?(pipeline_id.to_i, conversation: nil, inbox_id: inbox_id.to_i)

    blocked(inbox_id, pipeline_id)
  end

  def for_cards(cards)
    cards.first(MAX_CARDS).to_h { |card| [card.id, blocked(card.inbox_id, card.pipeline_id)] }
  end

  private

  def blocked_for_pair(inbox_id, pipeline_id)
    chave = [inbox_id.to_i, pipeline_id.to_i]
    @blocked[chave] ||= users_with_access(chave.first).reject do |user_id|
      @guard.owner_allowed?(user_id, inbox_id: chave.first, pipeline_id: chave.last)
    end
  end

  def users_with_access(inbox_id)
    Crm::InboxAgentAccess.where(account_id: @account.id, inbox_id: inbox_id).pluck(:user_id)
  end
end

# Que convites mostram um cliente que a pessoa pode ver (#1194, J8-A12). Usa as regras do próprio sistema, em SQL,
# para paginar sem vazar:
#   - pela conversa do convite: o mesmo filtro da lista de conversas (`Conversations::PermissionFilterService`,
#     caixas da pessoa e, com função, as chaves de conversa);
#   - pelo card do convite: o escopo de cards do CRM (`Crm::CardPolicy::Scope`), só para quem vê cards
#     (`Crm::CardPolicy#index?`: no EE, `crm_view`);
#   - convite só com o contato (sem card nem conversa): só quem o criou.
# Administrador vê todos.
class Crm::BookingV2::ClientVisibility
  def initialize(account:, user:, account_user:)
    @account = account
    @user = user
    @account_user = account_user
  end

  def apply(invites)
    return invites if account_user&.administrator?

    visible = invites.where(conversation_id: visible_conversations.select(:id))
    visible = visible.or(invites.where(card_id: visible_cards.select(:id))) if sees_cards?
    visible.or(invites.where(created_by_id: user.id, card_id: nil, conversation_id: nil))
  end

  # Ids, entre os informados, das conversas que a pessoa vê (uma consulta para a página inteira).
  def visible_conversation_ids(ids)
    return ids.compact.uniq if account_user&.administrator?

    visible_conversations.where(id: ids.compact.uniq).pluck(:id)
  end

  def card_visible?(card)
    card.present? && sees_cards? && visible_cards.exists?(id: card.id)
  end

  private

  attr_reader :account, :user, :account_user

  def context
    { user: user, account: account, account_user: account_user }
  end

  def visible_conversations
    @visible_conversations ||= Conversations::PermissionFilterService.new(account.conversations, user, account).perform
  end

  def visible_cards
    @visible_cards ||= Crm::CardPolicy::Scope.new(context, Crm::Card).resolve
  end

  def sees_cards?
    return @sees_cards if defined?(@sees_cards)

    @sees_cards = Crm::CardPolicy.new(context, Crm::Card).index?
  end
end

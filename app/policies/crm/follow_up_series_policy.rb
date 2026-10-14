# #1460 — a série de um lembrete que repete segue a regra das vezes dela: com card, ver o card e, para mexer, estar
# no funil (CardGuard, #1148); sem card, quem marcou, quem recebe e o administrador (StandaloneVisibility).
class Crm::FollowUpSeriesPolicy < ApplicationPolicy
  def show?
    Scope.new(user_context, Crm::FollowUpSeries).resolve.exists?(id: record.id)
  end

  def update?
    show? && card_funnel_member?
  end

  def pause?
    update?
  end

  def resume?
    update?
  end

  def finish?
    update?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      visible_card_ids = Pundit.policy_scope!(user_context, Crm::Card).select(:id)
      base = scope.where(account_id: account.id)
      standalone = Crm::FollowUps::StandaloneVisibility.new(user: user, account: account, account_user: account_user)
      base.where(card_id: visible_card_ids).or(standalone.apply(base.where(card_id: nil)))
    end
  end

  private

  # Sem card, só quem marcou e o administrador mexem na série (quem recebe só vê).
  def card_funnel_member?
    card = record.card
    return account_user&.administrator? || record.created_by_id == user&.id if card.nil?

    Crm::Access::CardGuard.new(user: user, account: account, account_user: account_user).edit_allowed?(card)
  end
end

Crm::FollowUpSeriesPolicy.prepend_mod_with('Crm::FollowUpSeriesPolicy')

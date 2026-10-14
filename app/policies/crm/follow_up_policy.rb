class Crm::FollowUpPolicy < ApplicationPolicy
  def index?
    account_user.present?
  end

  # Sem card (#1461): quem marcou, quem recebe e o administrador (StandaloneVisibility).
  def show?
    return standalone_scope.exists?(id: record.id) if record.card_id.nil?

    visible_card_scope.exists?(id: record.card_id)
  end

  def create?
    account_user.present?
  end

  # Acesso por funil (#1148, decisão b): o lembrete é do card; mexer nele exige o funil do card.
  def update?
    show? && card_funnel_member?
  end

  def destroy?
    update?
  end

  # Sem card (#1461), quem recebe também conclui (o popup oferece "Concluir"); mudar, adiar, cancelar e apagar ficam com
  # quem marcou e o administrador.
  def complete?
    return show? if record.card_id.nil?

    update?
  end

  def cancel?
    update?
  end

  def reschedule?
    update?
  end

  def dismiss_reminder?
    show?
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

  def standalone_scope
    visibility = Crm::FollowUps::StandaloneVisibility.new(user: user, account: account, account_user: account_user)
    visibility.apply(Crm::FollowUp.where(account_id: account.id, card_id: nil))
  end

  def visible_card_scope
    Pundit.policy_scope!(user_context, Crm::Card)
  end

  def card_funnel_member?
    card = record.card
    return standalone_owner? if card.nil?

    Crm::Access::CardGuard.new(user: user, account: account, account_user: account_user).edit_allowed?(card)
  end

  def standalone_owner?
    account_user&.administrator? || record.created_by_id == user&.id
  end
end

Crm::FollowUpPolicy.prepend_mod_with('Crm::FollowUpPolicy')

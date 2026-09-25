class Crm::CardPolicy < ApplicationPolicy
  def index?
    account_user.present?
  end

  # Planilha com dado pessoal em lote (nome, telefone, e-mail): no OSS, só administrador.
  def export?
    account_user&.administrator? || false
  end

  def show?
    visible_scope.exists?(id: record.id)
  end

  def create?
    account_user.present?
  end

  def update?
    show?
  end

  def destroy?
    update?
  end

  def move?
    update?
  end

  def close?
    update?
  end

  def from_conversation?
    create?
  end

  def link_conversation?
    update?
  end

  def unlink_conversation?
    update?
  end

  def link_contact?
    update?
  end

  def unlink_contact?
    update?
  end

  def evaluate_ai?
    update?
  end

  def summarize?
    update?
  end

  def reset_auto_followup?
    update?
  end

  def current_ai_suggestion?
    show?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      Crm::Cards::VisibleScopeQuery.new(
        scope: scope,
        account: account,
        user: user,
        account_user: account_user
      ).perform
    end
  end

  private

  def visible_scope
    Pundit.policy_scope!(user_context, Crm::Card)
  end
end

Crm::CardPolicy.prepend_mod_with('Crm::CardPolicy')

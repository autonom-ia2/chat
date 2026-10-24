class Crm::PipelinePolicy < ApplicationPolicy
  def index?
    account_user.present?
  end

  def show?
    account_user.present? && record.account_id == account.id
  end

  def create?
    administrator?
  end

  def update?
    administrator? && record.account_id == account.id
  end

  def destroy?
    update?
  end

  # Funil arquivado (#2095): restaurar e a prévia do arquivamento (cards abertos, caixas) são de quem gerencia funis.
  def restore?
    update?
  end

  def archive_preview?
    destroy?
  end

  def manage_ai?
    administrator? && record.account_id == account.id
  end

  # Excluir de vez (#2096): só administrador, também no EE (ver Crm::CardPolicy#permanent_delete?).
  def permanent_delete?
    administrator? && record.account_id == account.id
  end

  class Scope < ApplicationPolicy::Scope
    # Acesso por funil (#1148, PR D): quem tem restrição lista só os funis dela (Kanban, etapas, lista de funis).
    def resolve
      Crm::Access::VisiblePipelines.new(user: user, account: account, account_user: account_user)
                                   .apply(scope.where(account_id: account.id))
    end
  end

  private

  def administrator?
    account_user&.administrator?
  end
end

Crm::PipelinePolicy.prepend_mod_with('Crm::PipelinePolicy')

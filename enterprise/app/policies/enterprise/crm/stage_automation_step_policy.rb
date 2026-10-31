module Enterprise::Crm::StageAutomationStepPolicy
  include CrmPermissions

  # #2414 F1.3 (D2/D4): o passo da automação de etapa pede as duas chaves, a do funil e a de automação.
  def create?
    crm_permission?('crm_manage_pipelines') && monta_automacao?
  end

  def update?
    crm_permission?('crm_manage_pipelines') && record.account_id == account.id && monta_automacao?
  end

  def destroy?
    update?
  end

  private

  def monta_automacao?
    account_user.present? && account_user.permission_granted?('automation_manage')
  end
end

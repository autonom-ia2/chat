module Enterprise::Crm::PipelinePolicy
  include CrmPermissions

  def index?
    crm_permission?('crm_view')
  end

  def show?
    crm_permission?('crm_view') && record.account_id == account.id
  end

  def create?
    crm_permission?('crm_manage_pipelines')
  end

  def update?
    crm_permission?('crm_manage_pipelines') && record.account_id == account.id
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
    crm_permission?('crm_manage_ai') && record.account_id == account.id
  end
end

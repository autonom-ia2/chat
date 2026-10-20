module Enterprise::Crm::ReportPolicy
  include CrmPermissions

  # Com `crm_numeros_lentes` (#1897, Decisão 2 do #1871) o agente sem função perde a equipe; a função continua pela chave.
  def view?
    return false if agente_sem_funcao? && Crm::Config.numeros_lentes_enabled?(account)

    crm_permission?('crm_view_reports')
  end

  private

  def agente_sem_funcao?
    account_user.present? && !account_user.administrator? && account_user.custom_role.blank?
  end
end

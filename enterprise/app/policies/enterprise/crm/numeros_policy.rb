module Enterprise::Crm::NumerosPolicy
  include CrmPermissions

  # "Só eu" é de quem trabalha no CRM: administrador, agente sem função e função com `crm_view` (ou `crm_admin`).
  def eu?
    crm_permission?('crm_view')
  end
end

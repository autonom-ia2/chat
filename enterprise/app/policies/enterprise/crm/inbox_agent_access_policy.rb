module Enterprise::Crm::InboxAgentAccessPolicy
  include CrmPermissions

  # Configurar quem vê o quê nas caixas é configuração de administrador do CRM: só crm_admin, nunca a pessoa comum.
  def index?
    crm_permission?('crm_admin')
  end

  def update?
    crm_permission?('crm_admin')
  end
end

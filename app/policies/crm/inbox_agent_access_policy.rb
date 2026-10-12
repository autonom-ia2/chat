# Caixas no CRM (#1149): quem configura o que chega em cada caixa e quem vê o quê. Decide a visão das outras pessoas,
# então no OSS é só do administrador; o EE abre para a função com crm_admin.
class Crm::InboxAgentAccessPolicy < ApplicationPolicy
  def index?
    administrator?
  end

  def update?
    administrator?
  end

  private

  def administrator?
    account_user&.administrator?
  end
end

Crm::InboxAgentAccessPolicy.prepend_mod_with('Crm::InboxAgentAccessPolicy')

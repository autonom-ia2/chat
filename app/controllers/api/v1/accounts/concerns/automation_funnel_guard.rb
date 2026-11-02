# Regra que mexe no funil pede também a chave de configurar funis (Autonomia::Automacao::RegraDoFunil, #2414 F1.3).
# Criar e mudar: o que a regra tem hoje e o que vai ter, como na guarda de integração. Copiar: a regra de origem.
# Apagar segue só com automation_manage. O administrador sempre pode.
module Api::V1::Accounts::Concerns::AutomationFunnelGuard
  extend ActiveSupport::Concern

  private

  def check_funnel_rule
    exige_funil! if funil.mexe?(params[:actions], params[:conditions]) || funil.mexe?(@automation_rule&.actions, @automation_rule&.conditions)
  end

  def check_funnel_rule_on_clone
    origem = Current.account.automation_rules.find_by(id: params[:automation_rule_id])
    exige_funil! if funil.mexe?(origem&.actions, origem&.conditions)
  end

  def exige_funil!
    raise Pundit::NotAuthorizedError unless funil.pode?(Current.account_user)
  end

  def funil = Autonomia::Automacao::RegraDoFunil
end

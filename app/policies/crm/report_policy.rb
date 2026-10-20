# Os números da equipe no CRM (painel de Números, uso de IA e o tempo real do gasto). Com CRM › Números por papel
# ligado na conta (`crm_numeros_lentes`, #1897, Decisão 2 do #1871), o agente comum deixa de ver a equipe e fica com a
# visão "Só eu" (Crm::NumerosPolicy); sem a flag, como antes.
class Crm::ReportPolicy < ApplicationPolicy
  def view?
    return false if account_user.blank?

    account_user.administrator? || !Crm::Config.numeros_lentes_enabled?(account)
  end
end

Crm::ReportPolicy.prepend_mod_with('Crm::ReportPolicy')

# Quem define as metas do mês em CRM › Números (#1991, F4 do #1871): a gaveta "Metas do mês" mostra o R$ de cada pessoa
# e grava a meta de todos (Decisão 1). No OSS, só o administrador. No EE, também a função com `crm_metas_manage` (ou
# `crm_admin`), com acesso ao CRM. O agente sem função nunca.
class Crm::MetasPolicy < ApplicationPolicy
  def manage?
    account_user.present? && account_user.permission_granted?('crm_metas_manage')
  end
end

Crm::MetasPolicy.prepend_mod_with('Crm::MetasPolicy')

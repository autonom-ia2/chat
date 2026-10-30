module Enterprise::Crm::MetasPolicy
  # A função define metas com `crm_metas_manage` e acesso ao CRM (`crm_view`), ou com `crm_admin`, que liga todas as
  # chaves do CRM. A chave sozinha, sem o CRM, não abre o R$ dos colegas. A meta é dinheiro: as duas formas pedem
  # também os valores em R$ (`sales_value_view`, #2075), que o `crm_admin` não liga.
  def manage?
    return true if account_user&.administrator?

    chaves = chaves_da_funcao
    chaves.include?('sales_value_view') &&
      (chaves.include?('crm_admin') || (chaves.include?('crm_metas_manage') && chaves.include?('crm_view')))
  end

  private

  def chaves_da_funcao
    account_user&.custom_role&.permissions || []
  end
end

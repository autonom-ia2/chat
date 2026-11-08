module Enterprise::Crm::AiStageSuggestionPolicy
  include CrmPermissions

  # Ler a sugestão (#2150, decisão do Rodrigo em 23/10): só com crm_manage_ai, a mesma chave de aceitar e dispensar.
  def read?
    crm_permission?('crm_manage_ai')
  end

  def show?
    read? && card_visible?
  end

  def accept?
    crm_permission?('crm_manage_ai') && card_visible?
  end

  def dismiss?
    crm_permission?('crm_manage_ai') && card_visible?
  end

  def evaluate?
    crm_permission?('crm_manage_ai') && card_visible?
  end
end

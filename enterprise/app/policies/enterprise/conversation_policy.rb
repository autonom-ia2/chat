module Enterprise::ConversationPolicy
  OPERATING_KEYS = %w[conversation_manage conversation_unassigned_manage conversation_participating_manage].freeze

  def show?
    return false unless super
    return true unless custom_role_permissions?

    permissions = custom_role_permissions
    return true if manage_all_conversations?(permissions)
    return true if permits_unassigned_manage?(permissions)

    permits_participating?(permissions)
  end

  # conversation_view lê toda conversa que a pessoa alcança pela caixa, time e funil, sem operar: as escritas seguem
  # em show?, que só olha o trio conversation_* (#1800).
  def view?
    return super unless reads_by_role?

    member_access?
  end

  def create?
    super && !(reads_by_role? && !custom_role_permissions.intersect?(OPERATING_KEYS))
  end

  # Apagar mensagem: quem tem cargo precisa da chave, além de operar a conversa. Agente sem cargo segue apagando (#1893).
  def delete_message?
    show? && (!custom_role_permissions? || custom_role_permissions.include?('conversation_message_delete'))
  end

  private

  def reads_by_role?
    custom_role_permissions? && custom_role_permissions.include?('conversation_view')
  end

  def manage_all_conversations?(permissions)
    permissions.include?('conversation_manage')
  end

  def permits_unassigned_manage?(permissions)
    return false unless permissions.include?('conversation_unassigned_manage')

    unassigned_conversation? || assigned_to_user?
  end

  def permits_participating?(permissions)
    return false unless permissions.include?('conversation_participating_manage')

    assigned_to_user? || participant?
  end

  # Inclui a que o robô passou e espera pessoa (#1377, opção b).
  def unassigned_conversation?
    record.awaiting_person?
  end

  def custom_role_permissions?
    account_user&.custom_role_id.present?
  end

  def custom_role_permissions
    account_user&.custom_role&.permissions || []
  end
end

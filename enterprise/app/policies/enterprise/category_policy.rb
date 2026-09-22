module Enterprise::CategoryPolicy
  # knowledge_base_manage implies knowledge_base_view (read-only help center, #452).
  # Escrever continua proibido para todos: ver CategoryPolicy.
  def show?
    @account_user.permission_granted?('knowledge_base_view') || super
  end
end

module Enterprise::ArticlePolicy
  # knowledge_base_manage implies knowledge_base_view (read-only help center, #452).
  # Escrever continua proibido para todos: ver ArticlePolicy.
  def show?
    @account_user.permission_granted?('knowledge_base_view') || super
  end
end

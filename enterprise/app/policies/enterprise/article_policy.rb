module Enterprise::ArticlePolicy
  def index?
    @account_user.custom_role&.permissions&.include?('knowledge_base_manage') || super
  end

  def update?
    @account_user.custom_role&.permissions&.include?('knowledge_base_manage') || super
  end

  # knowledge_base_manage implies knowledge_base_view (read-only help center, #452).
  def show?
    @account_user.permission_granted?('knowledge_base_view') || super
  end

  def edit?
    @account_user.custom_role&.permissions&.include?('knowledge_base_manage') || super
  end

  def create?
    @account_user.custom_role&.permissions&.include?('knowledge_base_manage') || super
  end

  def destroy?
    @account_user.custom_role&.permissions&.include?('knowledge_base_manage') || super
  end

  def reorder?
    @account_user.custom_role&.permissions&.include?('knowledge_base_manage') || super
  end
end

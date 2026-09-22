# A Central de Ajuda é só leitura no painel: o conteúdo vem do repositório (#501/#502).
# Nenhum usuário, de nenhuma conta e com nenhuma função, cria, altera ou apaga.
class CategoryPolicy < ApplicationPolicy
  def index?
    @account.users.include?(@user)
  end

  def show?
    @account_user.administrator?
  end

  def update? = false
  def edit? = false
  def create? = false
  def destroy? = false
  def reorder? = false
end

CategoryPolicy.prepend_mod_with('CategoryPolicy')

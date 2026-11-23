# A Central de Ajuda é só leitura no painel: o conteúdo vem do repositório (#501/#502).
# Nenhum usuário, de nenhuma conta e com nenhuma função, cria, altera ou apaga.
class ArticlePolicy < ApplicationPolicy
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
  # Fork (upgrade 4.20.1, #3120): the public portal does not honor preview links (#16555 neutralized), so no token.
  def preview_token? = false
end

ArticlePolicy.prepend_mod_with('ArticlePolicy')

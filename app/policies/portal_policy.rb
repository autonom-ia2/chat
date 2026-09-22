# A Central de Ajuda é só leitura no painel: o conteúdo vem do repositório (#501/#502).
# Nenhum usuário, de nenhuma conta e com nenhuma função, cria, altera ou apaga portal.
class PortalPolicy < ApplicationPolicy
  def index?
    @account.users.include?(@user)
  end

  def show?
    @account.users.include?(@user)
  end

  def ssl_status?
    @account.users.include?(@user)
  end

  def update? = false
  def edit? = false
  def create? = false
  def destroy? = false
  def archive? = false
  def logo? = false
  def send_instructions? = false
end

PortalPolicy.prepend_mod_with('PortalPolicy')

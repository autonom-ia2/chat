# Vigias e avisos do Guia (#935): só administrador. Vigia para quem não é administrador está fora
# do escopo, e o aviso só vai a administradores.
class Autonomia::Guide::VigiaPolicy < ApplicationPolicy
  def index? = administrador?
  def show? = administrador?
  def create? = administrador?
  def update? = administrador?
  def destroy? = administrador?

  private

  def administrador?
    account_user&.administrator? == true
  end
end

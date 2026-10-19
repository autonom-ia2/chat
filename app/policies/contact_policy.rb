class ContactPolicy < ApplicationPolicy
  def index?
    true
  end

  def active?
    true
  end

  def import?
    @account_user.administrator?
  end

  def export?
    @account_user.administrator?
  end

  def summary?
    index?
  end

  def search?
    true
  end

  def filter?
    true
  end

  def update?
    true
  end

  def contactable_inboxes?
    true
  end

  # Ligar e ver a origem do contato da conversa (#1849): no OSS, quem vê o contato.
  def call?
    show?
  end

  def origins?
    show?
  end

  # Vincular o contato a um card do CRM (#1849): no OSS, quem vê o contato.
  def attach?
    show?
  end

  def destroy_custom_attributes?
    true
  end

  def show?
    true
  end

  def create?
    true
  end

  def avatar?
    true
  end

  def destroy?
    @account_user.administrator?
  end
end

ContactPolicy.prepend_mod_with('ContactPolicy')

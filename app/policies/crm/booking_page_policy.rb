# Páginas de agendamento novas (#1187, J8): ler pede `agendamento_view`, escrever `agendamento_manage`
# (`_manage` implica `_view`; o administrador tem as duas). Agente comum sem função e função sem o módulo: nada.
# Nada aqui delega usuários, funções, integrações, conexão de caixas, conta ou faturamento.
#
# A gaveta antiga (`AgentBookingProfilePolicy`) continua só do administrador.
class Crm::BookingPagePolicy < ApplicationPolicy
  def index?
    view?
  end

  def show?
    view?
  end

  def people?
    view?
  end

  %i[create? update? destroy? publish? pause? preview_token? logo? photo? update_people? test_invite? reassign? reassign_preview?].each do |action|
    define_method(action) { manage? }
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(account_id: account.id).new_pages
    end
  end

  private

  def view?
    granted?('agendamento_view')
  end

  def manage?
    granted?('agendamento_manage')
  end

  def granted?(key)
    return false unless same_account?

    account_user&.permission_granted?(key) || false
  end

  def same_account?
    return true unless record.is_a?(ActiveRecord::Base)

    account.present? && record.account_id == account.id
  end
end

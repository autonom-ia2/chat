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

  %i[create? update? destroy? publish? pause? preview_token? logo? photo? update_people? test_invite? reassign? reassign_preview?
     notice_template_suggestions? notice_templates?].each do |action|
    define_method(action) { manage? }
  end

  # Criar modelos na Meta (#1272) escreve na conta do WhatsApp do cliente: só o administrador da conta.
  def create_notice_templates?
    manage? && account_user&.administrator? == true
  end

  # Link curto (#1282): conferir se um nome está livre responde sobre a instalação inteira; só quem gerencia páginas.
  def short_name?
    manage?
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

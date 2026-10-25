# LGPD (#2096, com a flag crm_arquivados): excluir o contato pelo DELETE de sempre deixa os cards do CRM sem dado pessoal
# (ContactCrmCards) e cancela antes a reunião futura deles. Se o calendário não cancela uma delas, ou se um card mudou sob
# a trava (uma reunião marcada no meio), o destroy volta atrás inteiro e a resposta é 422, com o mesmo código da exclusão
# definitiva. Fora do corpo do controller do upstream, que fica igual.
#
# Aqui o cancelamento roda dentro da transação do destroy (depois da trava de contato online do controller). Se uma
# segunda reunião falhar, a primeira já foi cancelada no Google ou na Microsoft e volta a "marcada" aqui; a
# sincronização do calendário (Crm::Meetings::SyncService) a cancela de novo ao ver o evento cancelado no provedor.
module ContactsControllerCrmCards
  extend ActiveSupport::Concern

  included do
    rescue_from Crm::ExclusaoDefinitiva::ReuniaoNaoCancelada, with: :render_crm_meeting_cancel_failed
    rescue_from Crm::ExclusaoDefinitiva::Mudou, with: :render_crm_cards_changed
    # Impasse com a conversão de um lead do mesmo contato (#2143): nada saiu, e a pessoa tenta de novo.
    rescue_from ActiveRecord::Deadlocked, with: :render_contact_busy
  end

  private

  def render_crm_meeting_cancel_failed(error)
    render json: { message: I18n.t('contacts.meeting_cancel_failed'), error: 'crm.permanent_delete.meeting_cancel_failed',
                   meeting_id: error.meeting_id, canceled_meeting_ids: error.canceladas }, status: :unprocessable_entity
  end

  def render_contact_busy
    render json: { message: I18n.t('contacts.busy_try_again'), error: 'contact_busy' }, status: :conflict
  end

  def render_crm_cards_changed(error)
    render json: { message: I18n.t('contacts.crm_cards_changed'), error: "crm.permanent_delete.#{error.motivo}",
                   canceled_meeting_ids: error.canceladas }, status: :unprocessable_entity
  end
end

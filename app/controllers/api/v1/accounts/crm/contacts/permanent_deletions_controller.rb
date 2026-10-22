# LGPD (#2096, Parte C): excluir o contato apagando de vez os cards dele junto, abertos, ganhos ou arquivados. A conversa
# do cliente fica. Só administrador (também no EE: quem tem contact_delete exclui o contato pelo DELETE de sempre, que
# deixa os cards sem contato) e com a palavra EXCLUIR digitada, como o card e o funil.
#
# Rota própria, e não um parâmetro no DELETE do contato: assim o Guia não a alcança (Autonomia::Guide::Acoes::SO_NA_TELA),
# e o DELETE contacts/:id de sempre continua igual.
class Api::V1::Accounts::Crm::Contacts::PermanentDeletionsController < Api::V1::Accounts::Crm::BaseController
  CONFIRMACAO = 'EXCLUIR'.freeze

  before_action :fetch_contact
  before_action :ensure_deletable!

  def create
    render json: { payload: { deleted_card_ids: ::Crm::ExclusaoDefinitiva.contato!(contact: @contact, user: Current.user) } }
  rescue ::Crm::Cards::Excluidor::ReuniaoNaoCancelada => e
    render_error('crm.permanent_delete.meeting_cancel_failed', meeting_id: e.meeting_id, canceled_meeting_ids: e.canceladas)
  rescue ::Crm::ExclusaoDefinitiva::Mudou => e
    render_error("crm.permanent_delete.#{e.motivo}", canceled_meeting_ids: e.canceladas)
  end

  private

  def fetch_contact
    @contact = Current.account.contacts.find(params[:contact_id])
  end

  def ensure_deletable!
    return render_error('crm.permanent_delete.admin_only', status: :forbidden) unless pode_excluir?
    return render_error('crm.permanent_delete.confirmation_mismatch') unless params[:confirmation].to_s.strip == CONFIRMACAO

    # A mesma trava do DELETE do contato: quem está online agora não é excluído.
    render_error('crm.permanent_delete.contact_online') if ::OnlineStatusTracker.get_presence(Current.account.id, 'Contact', @contact.id)
  end

  def pode_excluir?
    policy(::Crm::Card).permanent_delete? && policy(@contact).destroy?
  end

  def render_error(code, status: :unprocessable_entity, **details)
    render json: { error: code }.merge(details), status: status
  end
end

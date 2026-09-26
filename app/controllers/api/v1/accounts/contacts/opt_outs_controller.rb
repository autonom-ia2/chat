# Recusa manual de mensagens ativas (chat#713): o painel do contato marca e desfaz por aqui, nunca pelo PATCH comum.
# Quem pode editar o contato pode marcar e desfazer. Marcar não troca recusa de outra origem; desfazer tira a recusa de
# qualquer origem, com o registro de quem desfez no log.
class Api::V1::Accounts::Contacts::OptOutsController < Api::V1::Accounts::Contacts::BaseController
  before_action :authorize_contact_update

  def create
    @contact.opt_out!(source: 'manual', by: Current.user)
    render :show
  end

  def destroy
    @contact.opt_in!(by: Current.user)
    render :show
  end

  private

  def authorize_contact_update
    authorize @contact, :update?
  end
end

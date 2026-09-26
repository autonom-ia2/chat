# Recusa manual de mensagens ativas (chat#713): o painel do contato marca e desfaz por aqui, nunca pelo PATCH comum.
# Quem pode editar o contato pode marcar e desfazer. Marcar não troca recusa de outra origem. Desfazer só tira a recusa
# manual: a da Prospecção sai pelo "Desfazer" do lead e a do descadastro de e-mail não sai por aqui, porque a herança
# (Contacts::OptOutInheritance) a gravaria de novo na próxima edição do contato.
class Api::V1::Accounts::Contacts::OptOutsController < Api::V1::Accounts::Contacts::BaseController
  before_action :authorize_contact_update

  def create
    @contact.opt_out!(source: 'manual', by: Current.user)
    render :show
  end

  def destroy
    if @contact.opted_out? && @contact.opt_out_source != 'manual'
      return render json: { error: I18n.t('contacts.opt_out.undo_only_manual') }, status: :unprocessable_entity
    end

    @contact.release_manual_opt_out!(by: Current.user)
    render :show
  end

  private

  def authorize_contact_update
    authorize @contact, :update?
  end
end

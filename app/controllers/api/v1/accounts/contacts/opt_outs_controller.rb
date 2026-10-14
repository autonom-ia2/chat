# Recusa manual de mensagens ativas (chat#713): o painel do contato marca e desfaz por aqui, nunca pelo PATCH comum.
# Quem pode editar o contato pode marcar e desfazer. Marcar não troca recusa de outra origem. Desfazer tira a recusa
# manual e a do pedido de parar que a IA reconheceu na resposta a uma campanha (#1449): essa não tem outra tela, e é aqui
# que a equipe corrige um engano. A da Prospecção sai pelo "Desfazer" do lead, a do pedido de parar no follow-up sai pelo
# reset do follow-up no card (chat#1325) e a do descadastro de e-mail não sai por aqui, porque a herança
# (Contacts::OptOutInheritance) a gravaria de novo na próxima edição do contato.
class Api::V1::Accounts::Contacts::OptOutsController < Api::V1::Accounts::Contacts::BaseController
  UNDOABLE_SOURCES = %w[manual campaign_reply].freeze

  before_action :authorize_contact_update

  def create
    @contact.opt_out!(source: 'manual', by: Current.user)
    render :show
  end

  def destroy
    if @contact.opted_out? && UNDOABLE_SOURCES.exclude?(@contact.opt_out_source)
      return render json: { error: I18n.t('contacts.opt_out.undo_only_manual') }, status: :unprocessable_entity
    end

    release
    render :show
  end

  private

  # O pedido de parar na resposta a campanha vale pelo número: desfazer solta o número inteiro (#1449).
  def release
    return unless @contact.opted_out?
    return Contacts::CampaignReplyOptOut.release_number!(@contact, by: Current.user) if @contact.opt_out_source == 'campaign_reply'

    @contact.release_opt_out!(source: @contact.opt_out_source, by: Current.user)
  end

  def authorize_contact_update
    authorize @contact, :update?
  end
end

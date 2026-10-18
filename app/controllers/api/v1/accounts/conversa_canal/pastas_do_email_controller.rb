# Spam e Lixeira da caixa de e-mail no painel (#1809, fase 1). Atrás da chave `conversa_email_nova`.
#   GET :conversation_id → { pasta: 'spam' | 'lixeira' | nil }
#   PUT :conversation_id { pasta: 'spam' | 'lixeira' | '' } → { pasta } ('' volta para a Entrada)
# Quem vê a conversa move (ConversationPolicy#show?), como no Gmail: nada é apagado, tudo volta com um toque.
class Api::V1::Accounts::ConversaCanal::PastasDoEmailController < Api::V1::Accounts::ConversaCanal::BaseController
  skip_before_action :exigir_chave
  before_action :exigir_email_novo
  before_action :carregar_conversa

  def show
    render json: { pasta: ConversaCanal::PastaDoEmail.find_by(conversation_id: @conversa.id)&.pasta }
  end

  def update
    pasta = ConversaCanal::MoverParaPasta.new(conversation: @conversa, pasta: params[:pasta], user: Current.user).perform
    render json: { pasta: pasta }
  rescue ConversaCanal::MoverParaPasta::Recusa => e
    recusar(e.message)
  end

  private

  def carregar_conversa
    @conversa = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize @conversa, :show?
  end

  def exigir_email_novo
    head :not_found unless Current.account.feature_enabled?('conversa_email_nova')
  end
end

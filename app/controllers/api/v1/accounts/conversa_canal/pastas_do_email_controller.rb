# Spam e Lixeira da caixa de e-mail no painel (#1809, fase 1). Atrás da chave `conversa_email_nova`.
#   GET :conversation_id → { pasta: 'spam' | 'lixeira' | nil }
#   PUT :conversation_id { pasta: 'spam' | 'lixeira' | '' } → { pasta } ('' volta para a Entrada)
#   DELETE :conversation_id → exclui de verdade, só conversa que já está na Lixeira (422 fora dela)
# Quem vê a conversa move (ConversationPolicy#show?), como no Gmail: nada é apagado, tudo volta com um toque.
# "Excluir para sempre" também é de quem tem acesso à caixa (decisão do Rodrigo, 18/10), não só do administrador como
# o "apagar conversa" do Chatwoot; por isso só vale dentro da Lixeira. Usa o mesmo serviço do Chatwoot (apaga em
# segundo plano e impede o IMAP de trazer o e-mail de volta).
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

  def destroy
    na_lixeira = ConversaCanal::PastaDoEmail.exists?(conversation_id: @conversa.id, pasta: 'lixeira')
    return recusar(I18n.t('conversa_canal.pastas.so_na_lixeira')) unless na_lixeira

    ::Conversations::DeleteService.new(conversation: @conversa, user: Current.user, ip: request.ip).perform
    head :ok
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

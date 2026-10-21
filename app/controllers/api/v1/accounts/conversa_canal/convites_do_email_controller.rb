# Resposta ao convite de reunião que chegou no e-mail (#1984): PUT { conversation_id, resposta } em
# convites_do_email/:message_id, com resposta aceito, talvez ou recusado. Quem pode ler a conversa pode responder
# (ConversationPolicy#show?, que o EE estende), como na reação (#1702). Atrás da conversa com a cara do canal (404 sem ela)
# e da chave convite_da_reuniao (422 sem ela).
# Recusa (sem convite, caixa fora dos convidados, resposta inválida): 422 com a frase para a tela. Provedor ou servidor
# de e-mail fora: 502, e nada é gravado.
class Api::V1::Accounts::ConversaCanal::ConvitesDoEmailController < Api::V1::Accounts::ConversaCanal::BaseController
  before_action :buscar_mensagem

  # → { id, convite }
  def update
    convite = ConversaCanal::RespostaDoConvite.new(message: @mensagem, resposta: convite_params[:resposta], user: Current.user).perform
    render json: { id: @mensagem.id, convite: convite }
  rescue ConversaCanal::RespostaDoConvite::Recusa => e
    recusar(e.message)
  rescue ConversaCanal::RespostaDoConvite::FalhaNoEnvio
    render json: { error: I18n.t('conversa_canal.convite.falhou') }, status: :bad_gateway
  end

  private

  def buscar_mensagem
    conversa = Current.account.conversations.find_by!(display_id: convite_params[:conversation_id])
    authorize conversa, :show?
    @mensagem = conversa.messages.find(params[:id])
  end

  def convite_params
    params.permit(:conversation_id, :resposta)
  end
end

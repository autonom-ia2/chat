# Reação do atendente a uma mensagem do WhatsApp (#1702): POST { conversation_id, message_id, emoji }; emoji '' tira.
# Quem pode responder na conversa pode reagir: a mesma regra das mensagens (ConversationPolicy#show?, que o EE estende).
# Recusa (provedor, janela, caixa): 422 com a frase para a tela; nada é gravado.
class Api::V1::Accounts::ConversaCanal::ReacoesController < Api::V1::Accounts::ConversaCanal::BaseController
  before_action :buscar_mensagem

  # → { id, reactions: [{ emoji, sender_type, sender_id, at }] }
  def create
    mensagem = ConversaCanal::ReacaoDoAtendente.new(message: @mensagem, user: Current.user, emoji: reacao_params[:emoji]).perform
    render json: { id: mensagem.id, reactions: Array(mensagem.content_attributes.to_h['reactions']) }
  rescue ConversaCanal::ReacaoDoAtendente::Recusa => e
    recusar(e.message)
  end

  private

  def buscar_mensagem
    conversa = Current.account.conversations.find_by!(display_id: reacao_params[:conversation_id])
    authorize conversa, :show?
    @mensagem = conversa.messages.find(reacao_params[:message_id])
  end

  def reacao_params
    params.permit(:conversation_id, :message_id, :emoji)
  end
end

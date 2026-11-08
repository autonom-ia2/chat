# Reação do atendente a uma mensagem do WhatsApp (#1702) e do Instagram (#2113): POST { conversation_id, message_id, emoji };
# emoji '' tira. Quem pode responder na conversa pode reagir: a mesma regra das mensagens (ConversationPolicy#show?, que o
# EE estende). Recusa (provedor, janela, caixa, emoji ausente ou fora do formato): 422 com a frase para a tela; nada é gravado.
# Emoji que não é texto (lista, objeto) não passa no strong params e chega nil: recusa, nunca "tirar a reação".
# Chave da conta: na caixa Instagram, a da conversa do Instagram (`conversa_instagram`); nas outras, a da pele (404 sem ela).
class Api::V1::Accounts::ConversaCanal::ReacoesController < Api::V1::Accounts::ConversaCanal::BaseController
  CHAVE_DO_INSTAGRAM = 'conversa_instagram'.freeze

  before_action :buscar_mensagem

  # → { id, reactions: [{ emoji, sender_type, sender_id, at }] }
  def create
    mensagem = ConversaCanal::ReacaoDoAtendente.new(message: @mensagem, user: Current.user, emoji: reacao_params[:emoji]).perform
    render json: { id: mensagem.id, reactions: Array(mensagem.content_attributes.to_h['reactions']) }
  rescue ConversaCanal::ReacaoDoAtendente::Recusa => e
    recusar(e.message)
  end

  private

  def exigir_chave
    head :not_found unless Current.account.feature_enabled?(chave_da_conversa)
  end

  def chave_da_conversa
    conversa.inbox.instagram_direct? ? CHAVE_DO_INSTAGRAM : ConversaCanal::Pele::FLAG
  end

  def conversa
    @conversa ||= Current.account.conversations.find_by!(display_id: reacao_params[:conversation_id])
  end

  def buscar_mensagem
    authorize conversa, :show?
    @mensagem = conversa.messages.find(reacao_params[:message_id])
  end

  def reacao_params
    params.permit(:conversation_id, :message_id, :emoji)
  end
end

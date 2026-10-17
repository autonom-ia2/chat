# Base das leituras do "+" da conversa com a cara do canal (#1702): só com a chave da conta ligada (404 sem ela).
class Api::V1::Accounts::ConversaCanal::BaseController < Api::V1::Accounts::BaseController
  before_action :exigir_chave

  private

  def exigir_chave
    head :not_found unless Current.account.feature_enabled?('conversa_cara_do_canal')
  end

  def recusar(mensagem)
    render json: { error: mensagem }, status: :unprocessable_entity
  end
end

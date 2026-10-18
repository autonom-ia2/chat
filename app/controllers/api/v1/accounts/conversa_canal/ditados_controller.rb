# Ditado da resposta de e-mail (#1786). Atrás da chave `conversa_email_nova` (não da do WhatsApp).
#   GET  disponivel → { disponivel:, traducao: } (a conta tem IA para transcrever? e algo que traduza: o Google
#        Tradutor ligado ou a IA da conta, ConversaCanal::TraducaoSemGoogle)
#   POST (multipart, campo `audio`) → { texto } ou 422 { error } com a frase para a pessoa
class Api::V1::Accounts::ConversaCanal::DitadosController < Api::V1::Accounts::ConversaCanal::BaseController
  skip_before_action :exigir_chave
  before_action :exigir_email_novo

  def disponivel
    ia = ConversaCanal::Ditado.disponivel?(Current.account)
    google = Current.account.hooks.exists?(app_id: 'google_translate')
    render json: { disponivel: ia, traducao: ia || google }
  end

  def create
    render json: { texto: ConversaCanal::Ditado.new(account: Current.account, audio: params[:audio]).texto }
  rescue ConversaCanal::Ditado::Falha => e
    recusar(e.message)
  end

  private

  def exigir_email_novo
    head :not_found unless Current.account.feature_enabled?('conversa_email_nova')
  end
end

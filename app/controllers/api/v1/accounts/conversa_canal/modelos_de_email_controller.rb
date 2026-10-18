# Modelos de e-mail das Campanhas no "+" da resposta de e-mail (#1786). Atrás da chave `conversa_email_nova`.
#   GET            → { payload: [{ id, nome, categoria, miniatura }] } (modelos salvos da conta)
#   GET :id?conversation_id= → { id, nome, mjml, html, campos: [{ chave, valor, origem }] } (origem: contato | ia | vazio)
#   GET :id/previa           → { id, mjml, html } (miniatura na janela de escolher; sem campos e sem IA)
# Quem responde a conversa usa (ConversationPolicy#show?), sem precisar da permissão de Campanhas: "se o modelo está
# salvo, ele pode usar" (Rodrigo, 18/10).
class Api::V1::Accounts::ConversaCanal::ModelosDeEmailController < Api::V1::Accounts::ConversaCanal::BaseController
  skip_before_action :exigir_chave
  before_action :exigir_email_novo

  def index
    modelos = ConversaCanal::ModeloDeEmail.da_conta(Current.account).select(:id, :name, :category, :thumbnail_url)
    render json: { payload: modelos.map { |m| { id: m.id, nome: m.name, categoria: m.category, miniatura: m.thumbnail_url } } }
  end

  def show
    conversa = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize conversa, :show?
    modelo = ConversaCanal::ModeloDeEmail.da_conta(Current.account).find(params[:id])
    render json: ConversaCanal::ModeloDeEmail.new(modelo: modelo, conversation: conversa, user: Current.user).como_json
  end

  def previa
    modelo = ConversaCanal::ModeloDeEmail.da_conta(Current.account).find(params[:id])
    render json: { id: modelo.id, mjml: modelo.body_mjml, html: modelo.body_html }
  end

  private

  def exigir_email_novo
    head :not_found unless Current.account.feature_enabled?('conversa_email_nova')
  end
end

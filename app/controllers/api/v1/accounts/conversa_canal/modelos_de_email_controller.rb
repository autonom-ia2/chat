# Modelos de e-mail das Campanhas no "+" da resposta de e-mail (#1786). Atrás da chave `conversa_email_nova`.
#   GET            → { payload: [{ id, nome, categoria, miniatura }] } (modelos salvos da conta)
#   GET :id?conversation_id= → { id, nome, mjml, html, campos: [{ chave, valor, origem }] } (origem: contato | ia | vazio)
#   GET :id?contact_id=&inbox_id= → o mesmo, sem conversa (gaveta "Escrever", #1809): contato, atendente e conta
#                                   preenchem; sem conversa a IA não tem o que ler, e o resto vem vazio
#   GET :id/previa           → { id, mjml, html } (miniatura na janela de escolher; sem campos e sem IA)
# Quem responde a conversa usa (ConversationPolicy#show?), sem precisar da permissão de Campanhas: "se o modelo está
# salvo, ele pode usar" (Rodrigo, 18/10). Sem conversa, a mesma checagem de quem cria a conversa
# (ConversationsController#create): contato da conta (ContactPolicy#show?) e a caixa (InboxPolicy#show?).
class Api::V1::Accounts::ConversaCanal::ModelosDeEmailController < Api::V1::Accounts::ConversaCanal::BaseController
  skip_before_action :exigir_chave
  before_action :exigir_email_novo

  def index
    modelos = ConversaCanal::ModeloDeEmail.da_conta(Current.account).select(:id, :name, :category, :thumbnail_url)
    render json: { payload: modelos.map { |m| { id: m.id, nome: m.name, categoria: m.category, miniatura: m.thumbnail_url } } }
  end

  def show
    origem = params[:conversation_id].present? ? { conversation: conversa } : contato_e_caixa
    modelo = ConversaCanal::ModeloDeEmail.da_conta(Current.account).find(params[:id])
    render json: ConversaCanal::ModeloDeEmail.new(modelo: modelo, user: Current.user, **origem).como_json
  end

  def previa
    modelo = ConversaCanal::ModeloDeEmail.da_conta(Current.account).find(params[:id])
    render json: { id: modelo.id, mjml: modelo.body_mjml, html: modelo.body_html }
  end

  private

  def conversa
    Current.account.conversations.find_by!(display_id: params[:conversation_id]).tap { |c| authorize c, :show? }
  end

  # Sem conversa nem contato: 422 (ParameterMissing). Contato ou caixa de outra conta: 404.
  def contato_e_caixa
    contato = Current.account.contacts.find(params.require(:contact_id))
    authorize contato, :show?
    caixa = Current.account.inboxes.find(params.require(:inbox_id))
    authorize caixa, :show?
    { contato: contato, inbox: caixa }
  end

  def exigir_email_novo
    head :not_found unless Current.account.feature_enabled?('conversa_email_nova')
  end
end

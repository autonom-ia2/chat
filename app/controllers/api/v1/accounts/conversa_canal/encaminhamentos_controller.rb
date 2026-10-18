# Encaminhar mensagens como no WhatsApp (#1702).
# GET  ?termo= -> { payload: [{ id, nome, telefone, avatar, ultima_linha, caixa }] } (conversas que o usuário vê)
# POST { conversation_id, message_ids: [], conversation_ids: [] } -> { payload: [{ conversation_id, ok, erro }] }
# Quem encaminha precisa ver a origem e poder responder em cada destino: a mesma regra das mensagens
# (ConversationPolicy#show?, que o EE estende). Destino sem acesso: 401, nada é criado. Recusa do pedido: 422.
# Só pessoa, pelo painel: encaminhamento automatizado é sinal de spam para o WhatsApp. Pedido com `api_access_token`
# (robô, agente da Autonomia, integração, automação, campanha ou script com o token pessoal) recebe 403 antes de
# qualquer leitura; o painel entra pela sessão (devise_token_auth), nunca por esse cabeçalho.
class Api::V1::Accounts::ConversaCanal::EncaminhamentosController < Api::V1::Accounts::ConversaCanal::BaseController
  prepend_before_action :recusar_automacao
  before_action :exigir_pessoa

  def index
    destinos = ConversaCanal::DestinosDoEncaminhamento.new(user: Current.user, account: Current.account, termo: params[:termo]).perform
    render json: { payload: destinos }
  end

  def create
    origem = conversa_autorizada(encaminhamento_params[:conversation_id])
    destinos = ids_dos_destinos.map { |display_id| conversa_autorizada(display_id) }
    resultado = ConversaCanal::Encaminhamento.new(
      origem: origem, message_ids: encaminhamento_params[:message_ids], destinos: destinos, user: Current.user
    ).perform
    render json: { payload: resultado }
  rescue ConversaCanal::Encaminhamento::Recusa => e
    recusar(e.message)
  end

  private

  def recusar_automacao
    so_pessoa if authenticate_by_access_token?
  end

  def exigir_pessoa
    so_pessoa unless Current.user.is_a?(User)
  end

  def so_pessoa
    render json: { error: I18n.t('conversa_canal.encaminhar.so_pessoa') }, status: :forbidden
  end

  # O limite vem antes de buscar: pedido com destinos demais nem chega ao banco.
  def ids_dos_destinos
    ids = Array(encaminhamento_params[:conversation_ids]).compact_blank.uniq
    if ids.size > ConversaCanal::Encaminhamento::LIMITE_DE_DESTINOS
      raise ConversaCanal::Encaminhamento::Recusa,
            I18n.t('conversa_canal.encaminhar.destinos_demais', limite: ConversaCanal::Encaminhamento::LIMITE_DE_DESTINOS)
    end

    ids
  end

  def conversa_autorizada(display_id)
    conversa = Current.account.conversations.find_by!(display_id: display_id)
    authorize conversa, :show?
    conversa
  end

  def encaminhamento_params
    params.permit(:conversation_id, message_ids: [], conversation_ids: [])
  end
end

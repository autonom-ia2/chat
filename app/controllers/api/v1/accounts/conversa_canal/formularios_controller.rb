# Formulários aprovados (WhatsApp Flows) da caixa, para o "+" da conversa (#1702). Só caixa de WhatsApp oficial: o
# formulário não tem versão em texto (#1473), então não existe no WAHA.
class Api::V1::Accounts::ConversaCanal::FormulariosController < Api::V1::Accounts::ConversaCanal::BaseController
  before_action :buscar_caixa

  # GET ?inbox_id= → { payload: [{ id, nome, categorias }] }
  def index
    render json: { payload: formularios.lista }
  rescue ConversaCanal::FormulariosDaCaixa::Falha => e
    recusar(e.message)
  end

  # GET /:id/primeira_tela?inbox_id= → { tela }
  def primeira_tela
    render json: { tela: formularios.primeira_tela(params[:id].to_s) }
  rescue ConversaCanal::FormulariosDaCaixa::Falha => e
    recusar(e.message)
  end

  private

  def buscar_caixa
    @caixa = Current.account.inboxes.find(params[:inbox_id])
    authorize @caixa, :show?
    recusar(I18n.t('conversa_canal.formularios.so_oficial')) unless whatsapp_oficial?
  end

  def whatsapp_oficial?
    @caixa.channel_type == 'Channel::Whatsapp' && @caixa.channel.provider == 'whatsapp_cloud'
  end

  def formularios
    ConversaCanal::FormulariosDaCaixa.new(@caixa)
  end
end

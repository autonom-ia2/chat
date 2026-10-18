# Busca de endereço da Localização do "+" (#1702): sugestões enquanto a pessoa digita e o ponto do lugar escolhido.
# `termo` (e não `q`) para o texto digitado não ir para o log de parâmetros; `sessao` agrupa a busca no Google.
class Api::V1::Accounts::ConversaCanal::LugaresController < Api::V1::Accounts::ConversaCanal::BaseController
  before_action :exigir_google

  # GET ?termo=&sessao=  → { payload: [{ text, place_id }] }
  def index
    render json: { payload: busca.suggestions(params[:termo].to_s) }
  rescue Autonomia::Prospecting::SearchRunner::ProviderError => e
    recusar(e.message)
  end

  # GET /:id?sessao= → { nome, endereco, latitude, longitude }
  def show
    return recusar(I18n.t('conversa_canal.lugares.nao_encontrado')) unless ConversaCanal::BuscaDeLugar.id_do_google?(params[:id])

    render json: busca.details(params[:id].to_s)
  rescue Autonomia::Prospecting::SearchRunner::ProviderError => e
    recusar(e.message)
  end

  private

  def busca
    ConversaCanal::BuscaDeLugar.para(Current.account, sessao: params[:sessao])
  end

  def exigir_google
    recusar(I18n.t('conversa_canal.lugares.sem_chave')) unless ConversaCanal::BuscaDeLugar.configurada?
  end
end

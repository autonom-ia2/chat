# #3211 — os agentes prontos que a Autonom.ia mantém e a conta contrata (`Autonomia::Agents::Contratados`).
#
# GET  .../autonomia/contratados          -> { modelos: [chaves] }: só as chaves, os textos dos cartões são da tela;
#                                            vazio na conta sem a flag do modelo (ou sem as consultas prontas e o cofre).
# POST .../autonomia/contratados/:modelo  { nome_agente, nome_corretora, sobre_corretora } -> 201 com o agente, como no
#                                            `show`; a recusa é 422 com o código e o campo (`DadosDoContratado`).
# Leitura pede `autonomia_view`; contratar pede `autonomia_manage`, como criar qualquer agente (BaseController).
class Api::V1::Accounts::Autonomia::ContratadosController < Api::V1::Accounts::Autonomia::BaseController
  include ::Autonomia::DadosDoContratado

  def index
    render json: { modelos: ::Autonomia::Agents::Contratados.disponiveis(Current.account) }
  end

  def create
    contratar = ::Autonomia::Agents::Contratados::Contratar.new(account: Current.account, user: Current.user,
                                                                modelo: params[:modelo], **dados_da_corretora)
    @agent = contratar.call
    render 'api/v1/accounts/autonomia/agents/show', status: :created
  end
end

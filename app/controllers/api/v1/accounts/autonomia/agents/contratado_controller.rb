# #3211 — a corretora troca os dados do agente contratado: o nome do agente e o nome e a apresentação da corretora
# (`Contratados::DadosDaCorretora`, as mesmas conferências do "Contratar").
#
# PATCH .../agents/:agent_id/contratado { nome_agente, nome_corretora, sobre_corretora } -> 200 com o agente, como no
# `show`. Agente de outra conta, de sistema ou que não é contratado: 404. Recusa: 422 com o código e o campo.
# Escrita: pede `autonomia_manage` (BaseController).
class Api::V1::Accounts::Autonomia::Agents::ContratadoController < Api::V1::Accounts::Autonomia::BaseController
  include ::Autonomia::DadosDoContratado

  before_action :buscar_contratado

  def update
    ::Autonomia::Agents::Contratados::DadosDaCorretora.new(agent: @agent, **dados_da_corretora).call
    render 'api/v1/accounts/autonomia/agents/show'
  end

  private

  def buscar_contratado
    @agent = agents_scope.find(params[:agent_id])
    raise ActiveRecord::RecordNotFound unless @agent.contratado?
  end
end

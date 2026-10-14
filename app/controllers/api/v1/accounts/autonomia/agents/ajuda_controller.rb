# Tema 14 (#1434) — quem o ajudante ajuda e "quando chamar". O ajudante é um agente interno da conta; o vínculo é o
# `Specialist` com `delegate_agent_id`, gravado só por `Autonomia::Agents::Ajudantes.definir!`. Atrás da chave da Fase 2:
# desligada, a rota não existe para a conta (404), como a área inteira de Agentes.
class Api::V1::Accounts::Autonomia::Agents::AjudaController < Api::V1::Accounts::Autonomia::BaseController
  before_action :ensure_fase2
  before_action :fetch_agent

  def show
    render json: payload
  end

  # PUT { principal_ids: [..], quando: '...' } — troca o conjunto inteiro. Recusa (422) lista vazia, ajudante que não é
  # interno e principal que não serve (outra conta, a Lia, outro ajudante).
  def update
    ::Autonomia::Agents::Ajudantes.definir!(ajudante: @agent, principal_ids: params[:principal_ids], quando: params[:quando].to_s)
    render json: payload
  rescue ::Autonomia::Agents::Ajudantes::Recusado => e
    render_unprocessable(e.message)
  end

  private

  def ensure_fase2
    head :not_found unless ::Autonomia::Agents::Fase2.ligada?(Current.account)
  end

  def fetch_agent
    @agent = agents_scope.find(params[:agent_id])
  end

  def payload
    vinculos = @agent.vinculos_de_ajudante.includes(:agent).order(:id).select { |vinculo| vinculo.agent&.deleted_at.nil? }
    { ajudante_id: @agent.id, quando: vinculos.first&.description,
      principais: vinculos.map { |vinculo| { id: vinculo.agent.id, name: vinculo.agent.name } } }
  end
end

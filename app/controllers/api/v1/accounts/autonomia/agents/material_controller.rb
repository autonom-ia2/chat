# #1426 (tema 4b) — as conferências do material do agente (gaveta "O que sabe"). Leitura pede autonomia_view; resolver
# pede autonomia_manage (BaseController). Fora da Fase 2 e na Lia, a leitura volta vazia e a ação responde 422.
# #3200: o teste automático do material saiu; quem quer testar pergunta pelo Testar.
class Api::V1::Accounts::Autonomia::Agents::MaterialController < Api::V1::Accounts::Autonomia::BaseController
  before_action :fetch_agent

  def show
    render json: retrato
  end

  # A escolha da pessoa num problema (Material::Resolver).
  def resolver
    ::Autonomia::Agents::Material::Resolver.new(@agent, params[:problema_id], params[:escolha].to_s).resolver!
    render json: retrato
  rescue ::Autonomia::Agents::Material::Resolver::Invalido
    render_unprocessable(I18n.t('autonomia.material.problema_invalido'))
  end

  private

  def retrato
    ::Autonomia::Agents::Material::Retrato.new(@agent.reload).to_h
  end

  def fetch_agent
    @agent = agents_scope.find(params[:agent_id])
  end
end

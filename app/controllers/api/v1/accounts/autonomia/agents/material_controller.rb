# #1426 (tema 4b) — as conferências e o autoteste do material do agente (gaveta "O que sabe"). Leitura pede
# autonomia_view; resolver e pedir o autoteste pedem autonomia_manage (BaseController). Fora da Fase 2 e na Lia, a
# leitura volta vazia e as ações respondem 422: tudo como na main.
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

  # "Testar de novo": sem limite de pedidos; com uma rodada em andamento, devolve a dela.
  def autoteste
    estado = ::Autonomia::Agents::Material::Autoteste.pedir!(@agent, quando: 'pedido')
    return render_unprocessable(I18n.t('autonomia.material.autoteste_indisponivel')) if estado.nil?

    render json: retrato
  end

  private

  def retrato
    ::Autonomia::Agents::Material::Retrato.new(@agent.reload).to_h
  end

  def fetch_agent
    @agent = agents_scope.find(params[:agent_id])
  end
end

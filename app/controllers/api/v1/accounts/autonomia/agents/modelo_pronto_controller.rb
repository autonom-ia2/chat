# #2881 — o dono muda as listas do modelo pronto de ramo pelo RASCUNHO do agente: é o caminho da tela quando ela reabre
# um rascunho sem a conversa do Construtor (a página foi recarregada). O pedido, as recusas e a regra são os mesmos da
# conversa (`Autonomia::ListasDoModeloPronto`, `ModelosDeRamo::Edicao`): só enquanto o agente é rascunho, só agente que
# nasceu de um modelo, só conta com o pacote `seguros` e a flag. Nenhuma chamada de IA.
#
# PATCH .../agents/:agent_id/modelo_pronto -> o agente, como no `show`, já com as listas novas.
# Escrita: pede `autonomia_manage`, como toda escrita da área de Agentes; a lista de ferramentas pede também
# `autonomia_tools_manage`. Agente de outra conta ou de sistema: 404. Agente em modo manual: 422, como pela conversa
# (a instrução dele é do dono, e as listas não entram nela).
class Api::V1::Accounts::Autonomia::Agents::ModeloProntoController < Api::V1::Accounts::Autonomia::BaseController
  include ::Autonomia::ListasDoModeloPronto

  before_action :conferir_chave_de_ferramentas!
  before_action :buscar_agente
  rescue_from ActiveRecord::Deadlocked, with: :render_conflito_de_trava

  def update
    editar_modelo_pronto(agent: @agent)
    render 'api/v1/accounts/autonomia/agents/show'
  end

  private

  def buscar_agente
    @agent = agents_scope.find(params[:agent_id])
    raise ::Autonomia::Agents::Agent::ModoManual if @agent.manual?
  end
end

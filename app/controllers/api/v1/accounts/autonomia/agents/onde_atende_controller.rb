# chat#1720 — o "Salvar" da gaveta "Onde e quando {nome} responde": onde atende primeiro, onde recebe quando alguém
# passa e o "Quando atende", num pedido só e numa transação só (Autonomia::Agents::OndeAtende).
#
# PUT .../agents/:agent_id/onde_atende
#   primeiro_inbox_id: a caixa de "Sim, no canal" (ausente/nulo = "Não, só quando alguém passar a conversa");
#   area_inbox_ids:    as caixas de "Recebe quando alguém passar em" (ausente/nulo = as áreas ficam como estão);
#   response_window:   always | business_hours | outside_business_hours (opcional);
#   parar:             true quando a tela confirmou que o agente fica sem receber conversa em nenhum canal.
# 204 quando gravou; 422 { error, code } quando recusou (nada mudou). Caixa fora da conta: 404.
class Api::V1::Accounts::Autonomia::Agents::OndeAtendeController < Api::V1::Accounts::Autonomia::BaseController
  # O recurso é o agente: sem envelope no corpo (format: []), mas o Guia lê dele o formato de `response_window`
  # (a validação de inclusão do Agent: always | business_hours | outside_business_hours), em formatos-das-acoes.json.
  wrap_parameters ::Autonomia::Agents::Agent, format: []

  before_action :fetch_agent

  def update
    return recusar(:pedido_invalido) unless pedido_valido?

    resultado = ::Autonomia::Agents::OndeAtende.new(
      agent: @agent, primeiro: caixa_primeiro, areas: caixas_das_areas,
      response_window: janela, parar: parar?
    ).perform
    return recusar(resultado.code, inbox: resultado.inbox, motivo_da_area: resultado.motivo_da_area) unless resultado.ok?

    head :no_content
  end

  private

  def fetch_agent
    @agent = agents_scope.find(params[:agent_id])
  end

  def pedido_valido?
    ids = params[:area_inbox_ids]
    (janela.nil? || ::Autonomia::Agents::Operate::EngagementGate::RESPONSE_WINDOWS.include?(janela)) &&
      (ids.nil? || ids.is_a?(Array))
  end

  # O "Quando atende" é texto (um dos valores do Agent), ou nil quando não veio.
  def janela
    params[:response_window].to_s.presence
  end

  def caixa_primeiro
    return if params[:primeiro_inbox_id].blank?

    Current.account.inboxes.find(params[:primeiro_inbox_id])
  end

  # Todas da conta, ou 404. nil quando o pedido não mexe nas áreas.
  def caixas_das_areas
    return if params[:area_inbox_ids].nil?

    ids = Array(params[:area_inbox_ids]).map(&:to_i).uniq
    caixas = Current.account.inboxes.where(id: ids).to_a
    raise ActiveRecord::RecordNotFound if caixas.size != ids.size

    caixas
  end

  def parar?
    ActiveModel::Type::Boolean.new.cast(params[:parar]) == true
  end

  # A recusa de uma área usa o mesmo texto da API de canais (area_errors), com o nome da caixa.
  def recusar(code, inbox: nil, motivo_da_area: nil)
    valores = { nome: @agent.name, canal: inbox&.name.to_s }
    mensagem = if motivo_da_area
                 I18n.t("autonomia.agents.operate.area_errors.#{motivo_da_area}", **valores)
               else
                 I18n.t("autonomia.agents.onde_atende.#{code}", **valores)
               end
    render json: { error: mensagem, code: code.to_s }, status: :unprocessable_entity
  end
end

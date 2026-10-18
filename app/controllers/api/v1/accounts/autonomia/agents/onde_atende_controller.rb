# chat#1720 — o "Salvar" da gaveta "Onde e quando {nome} responde": onde atende primeiro, onde recebe quando alguém
# passa e o "Quando atende", num pedido só e numa transação só (Autonomia::Agents::OndeAtende).
# Só nas contas com a Fase 2 dos Agentes (Autonomia::Agents::Fase2): sem ela não existe área e a gaveta usa o fluxo de
# antes (as rotas de canais); aqui, 422 fase2_off.
#
# PUT .../agents/:agent_id/onde_atende
#   primeiro_inbox_id: a caixa de "Sim, no canal" (ausente/nulo = "Não, só quando alguém passar a conversa");
#   manter_primeiro:   true quando a pessoa não trocou o canal: as portas ficam como estão (primeiro_inbox_id é ignorado);
#   area_inbox_ids:    as caixas de "Recebe quando alguém passar em" (ausente/nulo = as áreas ficam como estão);
#   response_window:   always | business_hours | outside_business_hours (opcional);
#   parar:             true quando a tela confirmou que o agente fica sem receber conversa em nenhum canal.
# 204 quando gravou; 422 { error, code } quando recusou (nada mudou). Caixa fora da conta: 404.
# Regra G (#1788): só mexe em caixa que a pessoa alcança (membro ou inbox_manage; administrador sempre). Caixa que entra,
# ou porta que sai, fora do alcance: 422 fora_do_alcance. Área de hoje numa caixa fora do alcance, mesmo fora do pedido,
# fica como está (a pessoa não vê essa caixa); o agente continua atendendo lá.
class Api::V1::Accounts::Autonomia::Agents::OndeAtendeController < Api::V1::Accounts::Autonomia::BaseController
  # O recurso é o agente: sem envelope no corpo (format: []), mas o Guia lê dele o formato de `response_window`
  # (a validação de inclusão do Agent: always | business_hours | outside_business_hours), em formatos-das-acoes.json.
  wrap_parameters ::Autonomia::Agents::Agent, format: []

  before_action :fetch_agent

  def update
    return recusar(:fase2_off) unless ::Autonomia::Agents::Fase2.ligada?(Current.account)
    return recusar(:pedido_invalido) unless pedido_valido?

    pedido = ::Autonomia::Agents::OndeAtende::Pedido.new(
      primeiro: caixa_primeiro, manter_primeiro: manter_primeiro?, areas: caixas_das_areas, response_window: janela, parar: parar?,
      alcancavel: ::Autonomia::Agents::CaixaAlcancavel.new(account_user: Current.account_user)
    )
    resultado = ::Autonomia::Agents::OndeAtende.new(agent: @agent, pedido: pedido).perform
    return recusar(resultado.code, inbox: resultado.inbox, motivo_da_area: resultado.motivo_da_area) unless resultado.ok?

    head :no_content
  end

  private

  def fetch_agent
    @agent = agents_scope.find(params[:agent_id])
  end

  # Tipos do pedido: janela entre as aceitas, primeiro um id (inteiro) e áreas uma lista de ids.
  def pedido_valido?
    janela_valida? && (params[:primeiro_inbox_id].nil? || id?(params[:primeiro_inbox_id])) && areas_validas?
  end

  def janela_valida?
    janela.nil? || ::Autonomia::Agents::Operate::EngagementGate::RESPONSE_WINDOWS.include?(janela)
  end

  def areas_validas?
    ids = params[:area_inbox_ids]
    ids.nil? || (ids.is_a?(Array) && ids.all? { |id| id?(id) })
  end

  def id?(valor)
    (valor.is_a?(Integer) || valor.is_a?(String)) && Integer(valor.to_s, 10, exception: false).present?
  end

  # O "Quando atende" é texto (um dos valores do Agent), ou nil quando não veio.
  def janela
    params[:response_window].to_s.presence
  end

  def caixa_primeiro
    return if manter_primeiro? || params[:primeiro_inbox_id].blank?

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

  def manter_primeiro?
    ActiveModel::Type::Boolean.new.cast(params[:manter_primeiro]) == true
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

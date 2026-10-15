# Caixas no CRM → Quem cuida do quê? (#1447): os agentes de IA de cada caixa, como a tela mostra. Só existe com a Fase 2
# dos Agentes ligada na conta (Crm::Ai::Config.areas_ligadas?); sem ela a caixa não leva `ai_agents` e a tela esconde a
# parte dos agentes.
#
# - porta: o agente que atende primeiro (vínculo de porta, Agentes IA). Sem porta, a caixa só de pessoas (sem agente
#   externo) também recebe área (#1433); a caixa com agente externo não.
# - areas: os agentes vinculados como área na caixa, como as pessoas membros dela, com os funis de que cuidam.
#   `ultima_caixa`: tirar este agente daqui o faz parar de atender (é o único lugar onde ele trabalha).
# - disponiveis: quem a tela pode pôr como área (só para quem pode mexer em agentes, e só em caixa que aceita área).
#   `parado`: entrar na caixa liga o agente.
# - externo (só com `detalhe`, #1648): o agente externo que atende primeiro, { id, name } ou nil.
class Crm::Caixas::RetratoDosAgentes
  # `detalhe: true` só na caixa aberta (#1570): a lista de caixas não consulta o leitor.
  def initialize(account:, inbox_ids:, pode_mudar:, detalhe: false)
    @account = account
    @inbox_ids = inbox_ids
    @pode_mudar = pode_mudar
    @detalhe = detalhe
  end

  def ligado?
    return @ligado if defined?(@ligado)

    @ligado = Crm::Ai::Config.areas_ligadas?(@account)
  end

  def caixa(inbox_id)
    porta = vinculos.fetch(inbox_id, []).find(&:porta?)
    pode_mudar = @pode_mudar && aceita_area?(porta, inbox_id)
    {
      porta: porta && { id: porta.agent.id, name: porta.agent.name },
      pode_mudar: pode_mudar,
      areas: areas(inbox_id),
      disponiveis: pode_mudar ? disponiveis(inbox_id) : []
    }.merge(@detalhe ? { externo: externo(inbox_id) } : {})
  end

  private

  # #1648 — o agente externo (n8n, Zapier...) que atende primeiro: o AgentBotInbox ativo da caixa cujo robô não é
  # espelho de agente da plataforma. Espelho é qualquer agent_bot de autonomia_agent_inboxes, apagado ou não (a mesma
  # regra do Autonomia::Agents::RobosSemEspelho, #1626): o espelho de uma porta apagada não vira "agente externo".
  # Mais de uma linha (não há índice único por caixa): a mais antiga. { id, name } ou nil. Só na caixa aberta
  # (`detalhe`): a lista não faz uma consulta por caixa.
  def externo(inbox_id)
    vinculo = AgentBotInbox.active.includes(:agent_bot)
                           .where(inbox_id: inbox_id, account_id: @account.id)
                           .where.not(agent_bot_id: ::Autonomia::Agents::AgentInbox.select(:agent_bot_id))
                           .order(:id).first
    return if vinculo&.agent_bot.nil?

    { id: vinculo.agent_bot.id, name: vinculo.agent_bot.name }
  end

  # Com porta: como sempre (o principal parado é conferido ao salvar). Sem porta: o leitor único do Agentes IA diz se é
  # só de pessoas (sem agente externo). Na lista (sem `detalhe`) não consulta e devolve false: na lista, caixa sem
  # porta sai com `pode_mudar: false` e `disponiveis: []`. A lista não oferece agentes; só a caixa aberta vale para isso.
  def aceita_area?(porta, inbox_id)
    return true if porta
    return false unless @detalhe

    inbox = Inbox.find_by(id: inbox_id, account_id: @account.id)
    inbox.present? && ::Autonomia::Agents::Areas.caixa_aceita_area?(inbox, conferir_fase2: false).ok?
  end

  def areas(inbox_id)
    vinculos.fetch(inbox_id, []).select(&:area?).map(&:agent).sort_by { |agente| agente.name.to_s.downcase }.map do |agente|
      { id: agente.id, name: agente.name, pipeline_ids: funis.fetch([inbox_id, agente.id], []),
        parado: !agente.atende_cliente?, ultima_caixa: agente.operating? && caixas_por_agente[agente.id].to_i == 1 }
    end
  end

  def disponiveis(inbox_id)
    na_caixa = vinculos.fetch(inbox_id, []).map(&:autonomia_agent_id)
    candidatos.reject { |agente| na_caixa.include?(agente.id) }
              .map { |agente| { id: agente.id, name: agente.name, parado: !agente.operating? } }
  end

  # Os vínculos ativos das caixas da tela, com o agente (não apagado).
  def vinculos
    @vinculos ||= ::Autonomia::Agents::AgentInbox.kept.where(account_id: @account.id, inbox_id: @inbox_ids)
                                                 .includes(:agent).to_a
                                                 .select { |vinculo| vinculo.agent&.deleted_at.nil? }
                                                 .group_by(&:inbox_id)
  end

  # Quantas caixas cada agente tem (vínculos ativos, porta ou área), na conta inteira.
  def caixas_por_agente
    @caixas_por_agente ||= ::Autonomia::Agents::AgentInbox.kept.where(account_id: @account.id).group(:autonomia_agent_id).count
  end

  # { [inbox_id, agent_id] => [pipeline_id, ...] } na ordem do CRM, só funis ativos.
  def funis
    @funis ||= Crm::InboxAiAgent.joins(:pipeline).merge(Crm::Pipeline.active)
                                .where(account_id: @account.id, inbox_id: @inbox_ids)
                                .order('crm_pipelines.position', 'crm_pipelines.id')
                                .pluck(:inbox_id, :autonomia_agent_id, :pipeline_id)
                                .group_by { |inbox_id, agent_id, _| [inbox_id, agent_id] }
                                .transform_values { |linhas| linhas.map(&:last) }
  end

  # Agentes da conta que podem ser área (Agent#pode_ser_area?, #1433): fora rascunho, parado de propósito, interno,
  # sistema e ajudante. A Lia entra (#1433, "lia b").
  def candidatos
    @candidatos ||= ::Autonomia::Agents::Agent.podem_ser_area(@account).order(:name, :id).to_a
  end
end

# Caixas no CRM → Quem cuida do quê? (#1447): os agentes de IA de cada caixa, como a tela mostra. Só existe com a Fase 2
# dos Agentes ligada na conta (Crm::Ai::Config.areas_ligadas?); sem ela a caixa não leva `ai_agents` e a tela esconde a
# parte dos agentes.
#
# - porta: o agente que atende primeiro (vínculo de porta, Agentes IA). Sem porta nativa não há área.
# - areas: os agentes vinculados como área na caixa, como as pessoas membros dela, com os funis de que cuidam.
#   `ultima_caixa`: tirar este agente daqui o faz parar de atender (é o único lugar onde ele trabalha).
# - disponiveis: quem a tela pode pôr como área (só para quem pode mexer em agentes, e só em caixa com porta).
#   `parado`: entrar na caixa liga o agente.
class Crm::Caixas::RetratoDosAgentes
  def initialize(account:, inbox_ids:, pode_mudar:)
    @account = account
    @inbox_ids = inbox_ids
    @pode_mudar = pode_mudar
  end

  def ligado?
    return @ligado if defined?(@ligado)

    @ligado = Crm::Ai::Config.areas_ligadas?(@account)
  end

  def caixa(inbox_id)
    porta = vinculos.fetch(inbox_id, []).find(&:porta?)
    {
      porta: porta && { id: porta.agent.id, name: porta.agent.name },
      pode_mudar: @pode_mudar && porta.present?,
      areas: areas(inbox_id),
      disponiveis: @pode_mudar && porta ? disponiveis(inbox_id) : []
    }
  end

  private

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

  # Agentes da conta que podem ser área: não apagados e que falam com cliente (não interno, não de sistema).
  def candidatos
    @candidatos ||= ::Autonomia::Agents::Agent.kept.where(account_id: @account.id).order(:name, :id).to_a
                                              .reject { |agente| agente.actuation_internal? || agente.config&.dig('system_key').present? }
  end
end

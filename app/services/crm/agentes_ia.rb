# #1593 — os agentes de IA que a Atribuição do CRM e o "Passar para…" oferecem. A regra de quem pode receber é dos
# Agentes (Autonomia::Agents::PassarParaIa.destinos_possiveis / destinos_na_caixa: Fase 2 ligada, vínculo ativo na
# caixa e atendendo cliente); aqui o CRM só lê. Sem a Fase 2 tudo é vazio, e o CRM passa só para pessoas.
#
# A IA nunca entra no rodízio "Alguém da equipe" (decisão do Rodrigo, 15/10): recebe só quando escolhida em "A mesma
# pessoa", pedida pelo nome ou passada na conversa. Agente parado é como pessoa fora: a conversa vai para a equipe.
module Crm::AgentesIa
  # Como o agente aparece na lista de nomes que a IA do CRM recebe (`eligible_agents`): o modelo devolve o item
  # exatamente como está na lista, e o motor acha o agente por igualdade com este rótulo (nunca por texto livre).
  # O sufixo é nosso (não é texto do cliente): é por ele que o motor sabe que o nome pedido era de um agente, mesmo
  # quando o agente não pode mais receber.
  SUFIXO = ' (agente de IA)'.freeze

  module_function

  def ligado?(account)
    Crm::Ai::Config.areas_ligadas?(account)
  end

  def rotulo_de_agente?(sugestao)
    sugestao.to_s.strip.end_with?(SUFIXO.strip)
  end

  # Os agentes que podem receber esta conversa agora, por nome.
  def destinos(conversation)
    return [] if conversation.blank? || !ligado?(conversation.account)

    por_nome(::Autonomia::Agents::PassarParaIa.destinos_possiveis(conversation))
  end

  def destino(agent_id, conversation)
    return if agent_id.blank?

    destinos(conversation).find { |agente| agente.id == agent_id.to_i }
  end

  # { rótulo => agente } na forma que a IA do CRM recebe.
  def rotulos(conversation)
    destinos(conversation).index_by { |agente| "#{agente.name}#{SUFIXO}" }
  end

  # Com "Se o cliente pedir alguém pelo nome" ligado, os rótulos que a IA do CRM recebe junto dos nomes das pessoas.
  def rotulos_pelo_nome(conversation, settings)
    settings[:selector_mode] == 'direct' ? rotulos(conversation).keys : []
  end

  # A regra salva já apontava este agente: salvar o resto da Atribuição não pede de novo (a Fase 2 pode ter sido
  # desligada, ou o agente parado, depois). Agente novo: escolhivel?.
  def pode_salvar?(account, novo, antes)
    antes = (antes || {}).to_h
    return true if antes['pool_type'] == 'ai_agent' && novo['pool_id'].to_i.positive? && antes['pool_id'].to_i == novo['pool_id'].to_i

    escolhivel?(account, novo['pool_id'])
  end

  # Pode ser salvo em "A mesma pessoa" (pool_type 'ai_agent'): com a Fase 2, agente desta conta que fala com cliente.
  # Parado pode: a tela avisa, e enquanto isso a conversa vai para alguém da equipe. Interno, de sistema, de outra conta
  # ou inexistente, não.
  def escolhivel?(account, agent_id)
    return false unless ligado?(account)

    agente = ::Autonomia::Agents::Agent.kept.find_by(account_id: account.id, id: agent_id)
    agente.present? && !agente.actuation_internal? && agente.config&.dig('system_key').blank?
  end

  # O agente cujo espelho é o dono (ai_assignee) da conversa, na caixa dela. Lê só a conta da conversa.
  def dono(conversation)
    return if conversation.blank? || conversation.ai_assignee_type != 'AgentBot' || conversation.assignee_agent_bot_id.blank?

    ::Autonomia::Agents::AgentInbox.kept.includes(:agent)
                                   .find_by(account_id: conversation.account_id, inbox_id: conversation.inbox_id,
                                            agent_bot_id: conversation.assignee_agent_bot_id)&.agent
  end

  # Para a tela de Atribuição do funil: quem pode receber, com as caixas do funil em que pode. `escolhidos`: os agentes
  # que as regras salvas já apontam; o que não pode mais receber em nenhuma caixa (parou, saiu delas) vem com
  # `parado: true`, para a tela avisar que a conversa está indo para alguém da equipe. nil sem a Fase 2.
  def do_funil(pipeline, escolhidos: [])
    return unless ligado?(pipeline.account)

    agentes = caixas_por_agente(pipeline)
    lista = agentes.map { |agente, caixas| { id: agente.id, name: agente.name, parado: false, caixas: caixas } }
    lista += parados(pipeline, escolhidos - agentes.keys.map(&:id))
    lista.sort_by { |agente| [agente[:name].to_s.downcase, agente[:id]] }
  end

  # { agente => [{ id:, name: } das caixas do funil em que ele pode receber] }
  def caixas_por_agente(pipeline)
    pipeline.inboxes.order(:name, :id).each_with_object({}) do |inbox, agentes|
      ::Autonomia::Agents::PassarParaIa.destinos_na_caixa(inbox).each do |agente|
        (agentes[agente] ||= []) << { id: inbox.id, name: inbox.name }
      end
    end
  end

  def parados(pipeline, ids)
    return [] if ids.empty?

    ::Autonomia::Agents::Agent.kept.where(account_id: pipeline.account_id, id: ids)
                              .map { |agente| { id: agente.id, name: agente.name, parado: true, caixas: [] } }
  end

  def por_nome(agentes)
    Array(agentes).sort_by { |agente| [agente.name.to_s.downcase, agente.id] }
  end
  private_class_method :caixas_por_agente, :parados, :por_nome
end

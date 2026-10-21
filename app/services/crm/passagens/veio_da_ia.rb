# #2067: de qual agente de IA veio a conversa que está com uma pessoa, para o "Devolver para <agente>" da caixa de
# resposta. Lê o registro de passagens (#1606): a passagem em aberto mais recente da conversa foi de uma IA para a pessoa
# que está com ela agora. Pessoa que recebeu de outra pessoa (IA → Ana → Bia) não vê: a Bia não recebeu da IA.
#
# A devolução é a atribuição de robô de hoje (POST assignments, assignee_type AgentBot), então aqui sai o robô para onde
# a conversa volta, e o nome que a pessoa conhece:
# - agente nosso (o registro grava o agente, não o espelho): o espelho do vínculo ATIVO dele nesta caixa;
# - robô de outro sistema (n8n): ele mesmo, se ainda está ligado nesta caixa;
# - a IA passou sem ponta gravada (motivo da IA, `de` vazio): o robô ativo da caixa.
# Sem robô para onde voltar (vínculo removido, robô desligado), nada: a tela não oferece o que não funcionaria.
#
#   Crm::Passagens::VeioDaIa.da_lista(conversas) -> { conversation_id => { id:, name: } }  (consultas fixas por página)
#   Crm::Passagens::VeioDaIa.de(conversa)        -> { id:, name: } | nil
module Crm::Passagens::VeioDaIa
  AGENTE = 'Autonomia::Agents::Agent'.freeze
  ROBO = 'AgentBot'.freeze

  module_function

  def de(conversation)
    da_lista([conversation])[conversation.id]
  end

  def da_lista(conversations)
    com_pessoa = conversations.select { |conversation| conversation.assignee_id.present? }
    return {} if com_pessoa.empty?

    abertas = ultimas_abertas(com_pessoa.map(&:id))
    da_ia = com_pessoa.filter_map do |conversation|
      passagem = abertas[conversation.id]
      [conversation, passagem] if passagem && da_ia_para?(passagem, conversation)
    end
    resolver(da_ia)
  end

  # A mais recente em aberto de cada conversa, numa consulta só (o índice parcial das abertas).
  def ultimas_abertas(ids)
    Crm::Passagem.abertas.where(conversation_id: ids)
                 .select('DISTINCT ON (crm_passagens.conversation_id) crm_passagens.*')
                 .reorder(:conversation_id, id: :desc)
                 .index_by(&:conversation_id)
  end

  # Para a pessoa que está com a conversa, vinda de uma IA: a ponta gravada não é pessoa, ou não há ponta e o motivo é
  # da IA (Crm::Passagem::MOTIVOS_DA_IA, o mesmo critério do filtro "Recebidas da IA").
  def da_ia_para?(passagem, conversation)
    return false unless passagem.para_type == 'User' && passagem.para_id == conversation.assignee_id
    return passagem.de_type != 'User' if passagem.de_type.present?

    Crm::Passagem::MOTIVOS_DA_IA.include?(passagem.motivo)
  end

  def resolver(pares)
    return {} if pares.empty?

    espelhos = espelhos_dos_agentes(pares)
    ativos = robos_ativos(pares)
    nomes = AgentBot.where(id: ativos.values.flatten.uniq).pluck(:id, :name).to_h
    pares.each_with_object({}) do |(conversation, passagem), mapa|
      robo = robo_de(passagem, conversation, espelhos, ativos)
      mapa[conversation.id] = { id: robo, name: passagem.de_nome.presence || nomes[robo] } if robo
    end
  end

  def robo_de(passagem, conversation, espelhos, ativos)
    da_caixa = ativos[conversation.inbox_id] || []
    case passagem.de_type
    when AGENTE then espelhos[[passagem.de_id, conversation.inbox_id]]
    when ROBO then passagem.de_id if da_caixa.include?(passagem.de_id)
    else da_caixa.first
    end
  end

  # [agente, caixa] => espelho do vínculo ativo, na conta da conversa.
  def espelhos_dos_agentes(pares)
    agentes = pares.filter_map { |_conversation, passagem| passagem.de_id if passagem.de_type == AGENTE }
    return {} if agentes.empty?

    vinculos_ativos(agentes, pares.map(&:first)).to_h { |agente, caixa, robo| [[agente, caixa], robo] }
  end

  def vinculos_ativos(agentes, conversas)
    Autonomia::Agents::AgentInbox.kept
                                 .where(autonomia_agent_id: agentes, inbox_id: conversas.map(&:inbox_id).uniq,
                                        account_id: conversas.map(&:account_id).uniq)
                                 .pluck(:autonomia_agent_id, :inbox_id, :agent_bot_id)
  end

  # caixa => robôs ligados nela (AgentBotInbox ativo).
  def robos_ativos(pares)
    AgentBotInbox.active.where(inbox_id: pares.map { |conversation, _passagem| conversation.inbox_id }.uniq)
                 .pluck(:inbox_id, :agent_bot_id)
                 .group_by(&:first).transform_values { |linhas| linhas.map(&:last) }
  end
end

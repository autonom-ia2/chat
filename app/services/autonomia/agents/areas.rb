# #1433 F1a — o agente da equipe numa caixa (vínculo de papel 'area').
#
# Chamado pela tela do CRM "Caixas no CRM → Quem cuida do quê?" (#1447) ao marcar/desmarcar o agente num funil da
# caixa. A área recebe a conversa quando alguém passa (pessoa ou outra IA, pela Atribuição do CRM: o espelho dela vira
# o ai_assignee) e responde com o PRÓPRIO espelho — Autonomia::Agents::QuemResponde escolhe quem responde.
#
# O espelho da área NÃO tem AgentBotInbox: assim inbox.agent_bot continua sendo a porta, e conversa nova continua
# nascendo com a porta (Conversation#set_active_bot_conversation).
#
# Caixa só de pessoas (#1433, decisão do Rodrigo de 15/10 na #1593): sem porta e sem robô de fora (AgentBotInbox, como
# o n8n), a área também pode entrar. Ali conversa nova nasce sem robô, então a área só responde quando vira dona da
# conversa por uma passagem; ela nunca abre conversa sozinha (QuemResponde: sem dono e sem porta, ninguém responde).
# Caixa com robô de fora continua recusada (CaixaComRoboExterno).
#
# Os dois métodos são idempotentes e rodam em transação. Soltar arquiva o vínculo (deleted_at) e GUARDA o espelho:
# ele é o autor das mensagens que a área já mandou (destruir o AgentBot apagaria o autor delas). Vincular de novo
# reativa o mesmo vínculo e o mesmo espelho.
#
# Ponto de extensão (fora da F1a): a ferramenta passar_para_area, os limites e a assinatura do evento
# crm.ai.responsible_agent_changed entram depois, sobre estes dois métodos e o QuemResponde.
module Autonomia::Agents::Areas
  class AgenteInterno < StandardError; end
  class AgenteNaoAtende < StandardError; end
  class AgenteDeSistema < StandardError; end
  class SemPortaAtendendo < StandardError; end
  class CaixaComRoboExterno < StandardError; end

  module_function

  # -> o AgentInbox de área ativo. Recusa o agente que não fala com cliente (mesmo predicado do
  # InboxConnector#connect_locked!, mais o de sistema). CaixaComRoboExterno quando a caixa não tem porta ativa e tem
  # robô de fora; ActiveRecord::RecordInvalid quando o agente já é a porta dela, ou agente/caixa são de contas
  # diferentes. Caixa sem porta e sem robô (só de pessoas) aceita.
  #
  # `ativar: true` (#1366) — "pôr o agente nesta área e ligá-lo": aceita o agente parado ou em rascunho e o liga
  # (active + enabled) na MESMA transação do vínculo, como o InboxConnector. É o caminho da área que volta depois que
  # o agente parou por ter ficado sem onde trabalhar. Sem `ativar`, só vincula quem já atende.
  #
  # `exigir_porta_atendendo: true` (#1433, tela do agente da equipe) — com a caixa já travada, confere que o principal
  # dela (a porta), SE HOUVER, está atendendo; senão SemPortaAtendendo. A tela só oferece caixas assim, mas o principal
  # pode parar entre a leitura e o clique. Caixa sem porta não tem principal a conferir.
  #
  # TRAVA O AGENTE E DEPOIS A CAIXA (#1366), a ordem de todos os caminhos (InboxConnector, SoftDelete,
  # AgentInbox#soltar_areas_da_caixa!): a conferência "a caixa tem porta ativa" e a saída da porta não se cruzam, e a
  # parada automática do agente não espera por uma caixa que outro segura.
  def vincular!(agent:, inbox:, ativar: false, exigir_porta_atendendo: false)
    agent.with_lock do
      # Confere com o agente já travado (e relido): uma pausa paralela não passa entre a conferência e o vínculo.
      recusar_quem_nao_fala_com_cliente!(agent, ativar: ativar)
      inbox.with_lock do
        conferir_a_caixa!(inbox, exigir_porta_atendendo)

        vinculo = vincular_na_caixa!(agent, inbox)
        # Depois do vínculo: a validação de atender já o enxerga. Recusada, a transação desfaz o vínculo.
        agent.update!(status: :active, enabled: true) if ativar && !agent.operating?
        vinculo
      end
    end
  end

  # Solta o vínculo de área do agente na caixa (se houver). As conversas que ele atendia voltam à porta; com
  # `porta_saindo: true` (a porta está saindo da caixa), vão direto para a equipe humana.
  # Nunca toca a porta: soltar a porta é o InboxConnector.
  # Agente e depois caixa, como o vincular!. Sendo a última área do agente, ele para (AgentInbox, #1366).
  def desvincular!(agent:, inbox:, porta_saindo: false)
    agent.with_lock do
      inbox.with_lock do
        vinculo = ::Autonomia::Agents::AgentInbox.kept.area.find_by(autonomia_agent_id: agent.id, inbox_id: inbox.id)
        next if vinculo.nil?

        vinculo.release_bot_conversations!(porta_saindo: porta_saindo)
        vinculo.update!(deleted_at: Time.current)
      end
    end
  end

  def vincular_na_caixa!(agent, inbox)
    vinculos = ::Autonomia::Agents::AgentInbox.where(autonomia_agent_id: agent.id, inbox_id: inbox.id)
    vinculos.kept.area.first || reativar!(vinculos.area.order(deleted_at: :desc).first) || criar!(agent, inbox)
  end

  def recusar_quem_nao_fala_com_cliente!(agent, ativar:)
    raise AgenteInterno, "agent #{agent.id} is internal and never talks to customers" if agent.actuation_internal?
    raise AgenteDeSistema, "agent #{agent.id} is a system agent" if agent.config&.dig('system_key').present?
    raise AgenteNaoAtende, "agent #{agent.id} is not operating" unless ativar || agent.operating?
  end

  # Com porta: só a exigência do principal atendendo. Sem porta: a caixa precisa ser só de pessoas (sem robô de fora).
  def conferir_a_caixa!(inbox, exigir_porta_atendendo)
    porta = ::Autonomia::Agents::AgentInbox.kept.porta.includes(:agent).find_by(inbox_id: inbox.id)
    if porta
      raise SemPortaAtendendo, "inbox #{inbox.id} has no operating porta" if exigir_porta_atendendo && !porta.agent&.operating?
    elsif ::Autonomia::Agents::AgentInbox.robo_externo_na_caixa?(inbox.id)
      raise CaixaComRoboExterno, "inbox #{inbox.id} has an external bot"
    end
  end

  def reativar!(vinculo)
    return if vinculo.nil?

    vinculo.update!(deleted_at: nil)
    vinculo
  end

  # Valida o vínculo antes de gravar o espelho: recusado, nenhum AgentBot fica para trás.
  def criar!(agent, inbox)
    espelho = AgentBot.new(account: agent.account, name: agent.name, bot_type: :webhook, outgoing_url: nil)
    ::Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: agent.account, agent_bot: espelho, papel: 'area')
  end
  private_class_method :vincular_na_caixa!, :recusar_quem_nao_fala_com_cliente!, :conferir_a_caixa!, :reativar!, :criar!
end

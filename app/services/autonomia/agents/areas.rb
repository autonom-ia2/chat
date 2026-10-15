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
# Caixa com agente de outro sistema (AgentBotInbox que não é espelho, como o n8n) também aceita a área (decisão do
# Rodrigo de 15/10 na #1648, opção B): conversa nova nasce com ele, e a área responde a conversa que alguém passar para
# ela. O risco de os dois responderem quando o outro sistema não filtra por dono ficou na #1636. Só nas contas com a
# aba "Agente de IA" por caixa (Autonomia::Agents::AgenteIaPorCaixa); nas outras, a regra de antes: caixa sem porta e
# com agente de outro sistema é recusada (CaixaNaoAceitaArea com :robo_externo).
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
  class AgenteRascunho < StandardError; end
  class AgenteNaoPodeSerArea < StandardError; end

  # O motivo de Agent#motivo_para_nao_ser_area vira o erro de cada um.
  RECUSAS = { interno: AgenteInterno, sistema: AgenteDeSistema, rascunho: AgenteRascunho,
              fora_da_equipe: AgenteNaoPodeSerArea }.freeze

  # A caixa não aceita agente da equipe agora; `codigo` é o do caixa_aceita_area? (ex.: :principal_parado).
  class CaixaNaoAceitaArea < StandardError
    attr_reader :codigo

    def initialize(codigo)
      @codigo = codigo
      super("inbox does not accept a team agent: #{codigo}")
    end
  end

  # Resposta de caixa_aceita_area?: `codigo` é um de CODIGOS.
  CODIGOS = %i[ok principal_parado robo_externo fase2_desligada].freeze
  Resultado = Struct.new(:codigo) do
    def ok?
      codigo == :ok
    end
  end

  module_function

  # O LEITOR ÚNICO de "esta caixa pode receber um agente da equipe agora?" (#1433), para a tela dos Agentes, o CRM e o
  # vincular!. Puro: não trava nada (o vincular! chama com a caixa já travada). -> Resultado com o código:
  # - :fase2_desligada — a conta DA CAIXA não tem a Fase 2 (sem ela a área nunca responde);
  # - :principal_parado — a caixa tem principal (porta ativa) e ele não está atendendo;
  # - :robo_externo — sem principal e com agente de outro sistema, na conta sem a aba "Agente de IA" por caixa;
  # - :ok — principal atendendo, ou caixa sem principal (só de pessoas ou, com a aba por caixa, com agente de outro
  #   sistema, #1648).
  # `conferir_fase2: false` é só do vincular!: a Fase 2 é regra da conta, conferida por quem chama (a API de canais e
  # a tela do CRM). O vincular! confere sempre a regra da CAIXA.
  # Tenancy: o principal é lido na conta da caixa.
  def caixa_aceita_area?(inbox, conferir_fase2: true)
    return Resultado.new(:fase2_desligada) if conferir_fase2 && !::Autonomia::Agents::Fase2.ligada?(inbox.account)

    porta = ::Autonomia::Agents::AgentInbox.kept.porta.includes(:agent).find_by(inbox_id: inbox.id, account_id: inbox.account_id)
    return Resultado.new(porta.agent&.operating? ? :ok : :principal_parado) if porta
    return Resultado.new(:robo_externo) if outro_sistema_barra_area?(inbox)

    Resultado.new(:ok)
  end

  # -> o AgentInbox de área ativo. Recusa o agente que não fala com cliente (mesmo predicado do
  # InboxConnector#connect_locked!, mais o de sistema). CaixaNaoAceitaArea (com o `codigo` do caixa_aceita_area?)
  # quando a caixa tem principal parado; ActiveRecord::RecordInvalid quando o agente já é a porta dela, ou agente/caixa
  # são de contas diferentes. Principal atendendo ou caixa sem principal (só de pessoas ou com agente de outro sistema)
  # aceita.
  #
  # Só entra quem `pode_ser_area?` (#1433), mesmo com `ativar`: senão AgenteInterno, AgenteDeSistema, AgenteRascunho
  # ou AgenteNaoPodeSerArea (ajudante, parado de propósito com caixa).
  #
  # `ativar: true` (#1366) — "pôr o agente nesta área e ligá-lo": aceita o agente parado SEM onde trabalhar e o liga
  # (active + enabled) na MESMA transação do vínculo, como o InboxConnector. É o caminho da área que volta depois que
  # o agente parou por ter ficado sem onde trabalhar. Sem `ativar`, só vincula quem já atende.
  #
  # `de_rascunho: true` (com `ativar`) — só a criação do agente da equipe (POST channels com papel area): aceita o
  # rascunho cuja conversa de criação já fechou (tem instrução). Rascunho pela metade é sempre recusado. O CRM não manda.
  #
  # A regra da caixa é conferida SEMPRE, com a caixa já travada, pelo mesmo leitor da tela (caixa_aceita_area?): a tela
  # só oferece caixas que aceitam, mas o principal pode parar entre a leitura e o clique.
  #
  # TRAVA O AGENTE E DEPOIS A CAIXA (#1366), a ordem dos caminhos da Autonom.ia (InboxConnector, SoftDelete): entre eles,
  # a conferência da caixa e a entrada ou saída de um principal não se cruzam, e a parada automática do agente não espera
  # por uma caixa que outro segura. O agente de outro sistema plugado pela caixa (set_agent_bot ou a troca da aba
  # Agente de IA, #1648) também trava a caixa; com área ele entra e a área fica. Registro em
  # spec/services/autonomia/agents/areas_agente_externo_depois_spec.rb.
  def vincular!(agent:, inbox:, ativar: false, de_rascunho: false)
    agent.with_lock do
      # Confere com o agente já travado (e relido): uma pausa paralela não passa entre a conferência e o vínculo.
      recusar_quem_nao_pode_ser_area!(agent, ativar: ativar, de_rascunho: de_rascunho)
      inbox.with_lock do
        conferir_a_caixa!(inbox)

        vinculo = vincular_na_caixa!(agent, inbox)
        # Depois do vínculo: a validação de atender já o enxerga. Recusada, a transação desfaz o vínculo.
        agent.update!(status: :active, enabled: true) if ativar && !agent.operating?
        vinculo
      end
    end
  end

  # Solta o vínculo de área do agente na caixa (se houver). As conversas que ele atendia voltam à porta; sem porta
  # atendendo (caixa só de pessoas), vão para a equipe humana.
  # Nunca toca a porta: soltar a porta é o InboxConnector.
  # Agente e depois caixa, como o vincular!. Sendo a última área do agente, ele para (AgentInbox, #1366).
  def desvincular!(agent:, inbox:)
    agent.with_lock do
      inbox.with_lock do
        vinculo = ::Autonomia::Agents::AgentInbox.kept.area.find_by(autonomia_agent_id: agent.id, inbox_id: inbox.id)
        next if vinculo.nil?

        vinculo.release_bot_conversations!
        vinculo.update!(deleted_at: Time.current)
      end
    end
  end

  # Sem a aba "Agente de IA" por caixa (#1648), a regra de antes da opção B: agente de outro sistema (ativo ou não) na
  # caixa sem porta não deixa a área entrar.
  def outro_sistema_barra_area?(inbox)
    !::Autonomia::Agents::AgenteIaPorCaixa.ligada_na_conta?(inbox.account_id) &&
      ::Autonomia::Agents::QuemAtendeACaixa.robos_de_outro_sistema(inbox, so_ativos: false).exists?
  end

  def vincular_na_caixa!(agent, inbox)
    vinculos = ::Autonomia::Agents::AgentInbox.where(autonomia_agent_id: agent.id, inbox_id: inbox.id)
    vinculos.kept.area.first || reativar!(vinculos.area.order(deleted_at: :desc).first) || criar!(agent, inbox)
  end

  def recusar_quem_nao_pode_ser_area!(agent, ativar:, de_rascunho:)
    motivo = agent.motivo_para_nao_ser_area(de_rascunho: de_rascunho && ativar)
    raise RECUSAS.fetch(motivo), "agent #{agent.id} cannot be a team agent (#{motivo})" if motivo
    raise AgenteNaoAtende, "agent #{agent.id} is not operating" unless ativar || agent.operating?
  end

  # O mesmo leitor da tela, com a caixa já travada.
  def conferir_a_caixa!(inbox)
    resultado = caixa_aceita_area?(inbox, conferir_fase2: false)
    raise CaixaNaoAceitaArea, resultado.codigo unless resultado.ok?
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
  private_class_method :outro_sistema_barra_area?, :vincular_na_caixa!, :recusar_quem_nao_pode_ser_area!, :conferir_a_caixa!, :reativar!, :criar!
end

# Caixas no CRM (#1149): cada caixa como a tela mostra. O que chega (funis ligados), o que o sistema faz sozinho e quem
# cuida de quê. Pessoa sem linha de acesso aparece como hoje vê: todos os funis, sem assunto e todas as conversas.
# Com a Fase 2 dos Agentes, cada caixa leva também `ai_agents` (Crm::Caixas::RetratoDosAgentes, #1447).
class Crm::Caixas::Retrato
  # `detalhe: true` (a caixa aberta, #1570): consulta se a caixa aceita agente de área novo. A lista não consulta.
  # `alcancavel` (regra G, #1788): só oferece mexer nos agentes das caixas que quem pede alcança.
  def initialize(account:, inboxes:, pode_mudar_agentes: false, detalhe: false, alcancavel: nil)
    @account = account
    @inboxes = inboxes.to_a
    @pode_mudar_agentes = pode_mudar_agentes
    @detalhe = detalhe
    @alcancavel = alcancavel
  end

  def caixas
    @inboxes.map { |inbox| caixa(inbox) }
  end

  def funis
    pipelines.map do |pipeline|
      {
        id: pipeline.id,
        name: pipeline.name,
        kind: pipeline.counts_as_sale? ? 'sales' : 'service',
        when_to_use: pipeline.when_to_use.to_s,
        ai_enabled: Crm::Ai::Config.enabled? && Crm::Subjects.ia_do_funil?(pipeline),
        stages: pipeline.stages.sort_by { |stage| [stage.position, stage.id] }.map { |stage| { id: stage.id, name: stage.name } }
      }
    end
  end

  def caixa(inbox)
    setting = settings[inbox.id]
    ligada = setting&.crm_enabled? || false
    {
      inbox: { id: inbox.id, name: inbox.name, channel_type: inbox.channel_type },
      crm_enabled: ligada,
      pipeline_ids: ligada ? links.fetch(inbox.id, []) : [],
      default_stage_id: setting&.default_stage_id,
      subject_ai_mode: setting&.subject_ai_mode || Crm::Caixas::IaDeAssunto.padrao(@account),
      auto_create_card: setting&.auto_create_card? || false,
      visibility_mode: setting&.visibility_mode || 'all_inbox_cards',
      agent_bot: robo(inbox),
      people: pessoas(inbox)
    }.merge(agentes_de_ia_da(inbox)).merge(do_detalhe(inbox))
  end

  private

  # A caixa aberta (#1682, decisão 7 do #1140): { funil => conversas em aberto desta caixa presas a um card aberto dele },
  # para a tela avisar antes de tirar um funil. Em aberto é aberta ou pendente. Presa ao card como no acesso por funil
  # (Crm::Access::ConversationScope): a conversa principal do card ou uma ligada a ele (crm_card_conversations).
  def do_detalhe(inbox)
    @detalhe ? { conversas_abertas: conversas_abertas(inbox) } : {}
  end

  def conversas_abertas(inbox)
    abertas = Conversation.where(inbox_id: inbox.id, status: Conversation.statuses.values_at('open', 'pending'))
    cards = Crm::Card.active.where(account_id: @account.id)
    principais = cards.where(conversation_id: abertas.select(:id)).pluck(:pipeline_id, :conversation_id)
    ligadas = Crm::CardConversation.where(conversation_id: abertas.select(:id), card_id: cards.select(:id))
                                   .joins(:card).pluck('crm_cards.pipeline_id', 'crm_card_conversations.conversation_id')
    (principais + ligadas).uniq.group_by(&:first).transform_values(&:size)
  end

  # O robô que atende primeiro na caixa. O card mostra este como responsável quando não há pessoa nem robô atribuído à
  # conversa (Crm::Card#responsible_agent_bot, #1377). `tipo_do_principal` (#1570): 'ia' quando o robô é espelho de
  # agente da plataforma; 'externo' em qualquer outro caso (n8n, Zapier...).
  # - Com a aba "Agente de IA" por caixa ligada na conta (#1648): espelho é a regra única de AgentInbox.espelhos, a
  #   mesma da aba, do `externo` e da lista de Agentes externos.
  # - Desligada: como antes, o espelho da porta ativa da caixa (AgentInbox porta não apagado, de agente não apagado).
  def robo(inbox)
    vinculo = inbox.agent_bot_inbox
    return unless vinculo&.active? && vinculo.agent_bot

    { id: vinculo.agent_bot.id, name: vinculo.agent_bot.name, tipo_do_principal: espelho?(inbox, vinculo) ? 'ia' : 'externo' }
  end

  def espelho?(inbox, vinculo)
    return espelhos.include?(vinculo.agent_bot_id) if agente_ia_por_caixa?

    espelhos_da_porta.include?([inbox.id, vinculo.agent_bot_id])
  end

  def agente_ia_por_caixa?
    return @agente_ia_por_caixa if defined?(@agente_ia_por_caixa)

    @agente_ia_por_caixa = ::Autonomia::Agents::AgenteIaPorCaixa.ligada?(@account)
  end

  # [[inbox_id, agent_bot_id], ...] das portas ativas das caixas da tela, numa consulta só. Agente apagado não conta,
  # como em RetratoDosAgentes#vinculos: lá a porta dele já não aparece.
  def espelhos_da_porta
    @espelhos_da_porta ||= ::Autonomia::Agents::AgentInbox.kept.porta
                                                          .where(account_id: @account.id, inbox_id: @inboxes.map(&:id))
                                                          .where(autonomia_agent_id: ::Autonomia::Agents::Agent.kept.select(:id))
                                                          .pluck(:inbox_id, :agent_bot_id).to_set
  end

  # Os robôs das caixas da tela que são espelho de agente da plataforma, numa consulta só.
  def espelhos
    @espelhos ||= ::Autonomia::Agents::AgentInbox
                  .where(agent_bot_id: AgentBotInbox.where(inbox_id: @inboxes.map(&:id)).select(:agent_bot_id))
                  .distinct.pluck(:agent_bot_id).to_set
  end

  def agentes_de_ia_da(inbox)
    agentes_de_ia.ligado? ? { ai_agents: agentes_de_ia.caixa(inbox.id) } : {}
  end

  def agentes_de_ia
    @agentes_de_ia ||= Crm::Caixas::RetratoDosAgentes.new(
      account: @account, inbox_ids: inbox_ids, pode_mudar: @pode_mudar_agentes, detalhe: @detalhe, alcancavel: @alcancavel
    )
  end

  def pessoas(inbox)
    lista = membros.fetch(inbox.id, []).filter_map do |user|
      account_user = account_users[user.id]
      next if account_user.nil? || account_user.integration?

      pessoa(inbox, user, account_user.administrator?)
    end
    lista.sort_by { |pessoa| Crm::OrdemDeNome.chave(pessoa[:name], pessoa[:id]) }
  end

  def pessoa(inbox, user, administrador)
    access = acessos[[inbox.id, user.id]]
    {
      id: user.id,
      name: user.available_name,
      administrator: administrador,
      triage: access.nil? || access.triage?,
      all_pipelines: access.nil? || access.all_pipelines?,
      pipeline_ids: access.nil? ? [] : access.agent_pipelines.map(&:pipeline_id),
      only_own: access.present? && access.only_own?
    }
  end

  def pipelines
    @pipelines ||= @account.crm_pipelines.active.includes(:stages).order(:position, :id).to_a
  end

  def settings
    @settings ||= @account.crm_inbox_settings.where(inbox_id: inbox_ids).index_by(&:inbox_id)
  end

  # Só funis ativos, na ordem do CRM.
  def links
    @links ||= @account.crm_pipeline_inboxes.where(inbox_id: inbox_ids, pipeline_id: pipelines.map(&:id))
                       .pluck(:inbox_id, :pipeline_id)
                       .group_by(&:first)
                       .transform_values { |pares| ordenar(pares.map(&:last)) }
  end

  def ordenar(pipeline_ids)
    ordem = pipelines.map(&:id)
    pipeline_ids.uniq.sort_by { |id| ordem.index(id) }
  end

  def membros
    @membros ||= InboxMember.where(inbox_id: inbox_ids).includes(:user).group_by(&:inbox_id)
                            .transform_values { |linhas| linhas.filter_map(&:user) }
  end

  def account_users
    @account_users ||= @account.account_users.where(user_id: membros.values.flatten.map(&:id)).index_by(&:user_id)
  end

  def acessos
    @acessos ||= Crm::InboxAgentAccess.where(account_id: @account.id, inbox_id: inbox_ids)
                                      .includes(:agent_pipelines).index_by { |access| [access.inbox_id, access.user_id] }
  end

  def inbox_ids
    @inbox_ids ||= @inboxes.map(&:id)
  end
end

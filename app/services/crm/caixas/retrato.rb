# Caixas no CRM (#1149): cada caixa como a tela mostra. O que chega (funis ligados), o que o sistema faz sozinho e quem
# cuida de quê. Pessoa sem linha de acesso aparece como hoje vê: todos os funis, sem assunto e todas as conversas.
class Crm::Caixas::Retrato
  def initialize(account:, inboxes:)
    @account = account
    @inboxes = inboxes.to_a
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
      subject_ai_mode: setting&.subject_ai_mode || 'off',
      auto_create_card: setting&.auto_create_card? || false,
      visibility_mode: setting&.visibility_mode || 'all_inbox_cards',
      agent_bot: robo(inbox),
      people: pessoas(inbox)
    }
  end

  private

  # O robô que atende primeiro na caixa. O card mostra este como responsável quando não há pessoa nem robô atribuído à
  # conversa (Crm::Card#responsible_agent_bot, #1377).
  def robo(inbox)
    vinculo = inbox.agent_bot_inbox
    return unless vinculo&.active? && vinculo.agent_bot

    { id: vinculo.agent_bot.id, name: vinculo.agent_bot.name }
  end

  def pessoas(inbox)
    lista = membros.fetch(inbox.id, []).filter_map do |user|
      account_user = account_users[user.id]
      next if account_user.nil? || account_user.integration?

      pessoa(inbox, user, account_user.administrator?)
    end
    lista.sort_by { |pessoa| pessoa[:name].to_s.downcase }
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

# Lista nova "o que fazer agora" (#2283). Cada card cai em um grupo, o primeiro que valer:
#   1 esperando  — a conversa principal, que a pessoa vê, espera resposta (waiting_since)
#   2 retorno    — retorno da pessoa (Crm::FollowUp.retorno_da_pessoa) de hoje ou atrasado, no fuso da conta
#   3 ninguem    — sem dono, sem pessoa e sem robô na conversa (espelho de Crm::Card#current_responsible), com a conversa
#                  visível ou sem conversa
#   4 parado     — sem mensagem e sem mudar de etapa há 7 dias ou mais (STALE_SQL), sem retorno da pessoa marcado
#   5 demais
# O grupo sai de um só CASE, num LEFT JOIN LATERAL, para a lista (sort=acao), os filtros (waiting, follow_up_status=due,
# mine, action_group) e a contagem (summaries?group_by=acao) nunca discordarem. Conversa que a pessoa não vê
# (visible_conversation_ids_sql) não conta para "esperando" nem para "ninguém cuidando".
#
# Incluído no Crm::Cards::FilterQuery, que dá @params, @account, @account_user e as regras de SharedFilters.
module Crm::Cards::ActionGroups
  KEYS = { 1 => 'esperando', 2 => 'retorno', 3 => 'ninguem', 4 => 'parado', 5 => 'demais' }.freeze
  SORT = 'acao'.freeze
  FOLLOW_UP_DUE = 'due'.freeze
  STALE_DAYS = 7
  # Para a página da lista: o grupo de cada card vem na própria linha (PayloadBuilder lê `acao_grupo`).
  SELECT = 'acao.grupo AS acao_grupo'.freeze
  GROUP_SQL = 'acao.grupo'.freeze
  CONVERSATION = 'acao_conversa'.freeze
  VISIBLE = 'acao_visivel'.freeze

  def self.sort?(params)
    params[:sort].to_s == SORT
  end

  private

  def apply_action_groups(cards)
    return cards unless action_groups_needed?

    # Condição e ordem em texto ou nó Arel, nunca hash com "acao.grupo": a chave com ponto põe `acao` em references_values
    # e liga o eager_load do includes da base (JOIN das conversas vinculadas, linhas repetidas, select descartado).
    cards = cards.joins(action_conversation_join)
    cards = cards.joins(action_visibility_join) unless @conversation_visibility.all_conversations?
    cards = cards.joins(action_follow_up_join).joins(action_group_lateral)
    cards = cards.where("#{GROUP_SQL} = 1") if boolean_param(:waiting)
    cards = cards.where('acao.retorno_em <= ?', end_of_today) if @params[:follow_up_status].to_s == FOLLOW_UP_DUE
    cards = apply_action_group_filter(cards)
    boolean_param(:mine) ? apply_mine(cards) : cards
  end

  # Grupo que não existe mostra a lista vazia, nunca a lista inteira (como o link de Origens com mês inválido).
  def apply_action_group_filter(cards)
    return cards if @params[:action_group].blank?
    return cards.none if action_group_param.nil?

    cards.where("#{GROUP_SQL} = ?", action_group_param)
  end

  def action_groups_needed?
    Crm::Cards::ActionGroups.sort?(@params) || @params[:group_by].to_s == SORT || boolean_param(:waiting) ||
      boolean_param(:mine) || @params[:follow_up_status].to_s == FOLLOW_UP_DUE || @params[:action_group].present?
  end

  # "Só meus" (#2283, decisão 6): o card é meu (dono) ou, sem dono, a conversa visível é minha; a conversa minha que
  # espera resposta entra mesmo com outro dono; e "ninguém cuidando" fica, porque o cliente sem dono pode ser meu.
  def apply_mine(cards)
    me = @account_user&.user_id
    return cards.none if me.blank?

    me = Integer(me)
    cards.where(<<~SQL.squish)
      crm_cards.owner_id = #{me}
      OR (crm_cards.owner_id IS NULL AND #{visible_action_conversation_sql} AND #{CONVERSATION}.assignee_id = #{me})
      OR (acao.grupo = 1 AND #{CONVERSATION}.assignee_id = #{me})
      OR acao.grupo = 3
    SQL
  end

  # Dentro do grupo: 1 SLA mais perto, depois quem espera há mais tempo · 2 retorno mais antigo · 3 quem entrou primeiro ·
  # 4 parado há mais tempo · 5 próximo retorno da pessoa, sem retorno no fim. Desempate: score desc, id desc (paginação
  # estável). Nós Arel, não texto: texto que começa com "acao." viraria references_values (ver apply_action_groups).
  def apply_action_sort(cards)
    terms = [asc('acao.grupo')]
    terms << asc(sla_order_sql).nulls_last if sla_order?
    terms.push(asc("CASE WHEN acao.grupo = 1 THEN #{CONVERSATION}.waiting_since END"),
               asc('CASE WHEN acao.grupo = 2 THEN acao.retorno_em END'),
               asc('CASE WHEN acao.grupo = 3 THEN crm_cards.created_at END'),
               asc("CASE WHEN acao.grupo = 4 THEN #{Crm::Cards::SharedFilters::STALE_SQL} END").nulls_first,
               asc('CASE WHEN acao.grupo = 5 THEN acao.retorno_em END').nulls_last,
               Arel::Nodes::Descending.new(Arel.sql('crm_cards.score')), Arel::Nodes::Descending.new(Arel.sql('crm_cards.id')))
    cards.reorder(*terms)
  end

  def asc(sql)
    Arel::Nodes::Ascending.new(Arel.sql(sql))
  end

  def action_conversation_join
    "LEFT JOIN conversations #{CONVERSATION} ON #{CONVERSATION}.id = crm_cards.conversation_id " \
      "AND #{CONVERSATION}.account_id = crm_cards.account_id"
  end

  def action_group_lateral
    # Valores citados à mão: a consulta de visibilidade vai dentro e não pode passar por troca de parâmetro nomeado.
    today_end = ActiveRecord::Base.connection.quote(end_of_today)
    stale_since = ActiveRecord::Base.connection.quote(STALE_DAYS.days.ago)
    <<~SQL.squish
      LEFT JOIN LATERAL (
        SELECT acao_retorno.em AS retorno_em,
          CASE
            WHEN #{visible_action_conversation_sql} AND #{CONVERSATION}.waiting_since IS NOT NULL THEN 1
            WHEN acao_retorno.em <= #{today_end} THEN 2
            WHEN #{nobody_cares_sql} THEN 3
            WHEN acao_retorno.em IS NULL AND (#{Crm::Cards::SharedFilters::STALE_SQL} IS NULL
              OR #{Crm::Cards::SharedFilters::STALE_SQL} < #{stale_since}) THEN 4
            ELSE 5
          END AS grupo
      ) acao ON TRUE
    SQL
  end

  # O retorno da pessoa mais perto de cada card, agregado uma vez para a conta (não por card, dentro do LATERAL): a
  # visibilidade das conversas dos lembretes vira um hash só, e o planejador não cobra a montagem dele a cada card. Só o
  # retorno sem conversa ou de conversa que a pessoa vê (Crm::FollowUp.retorno_visivel): o grupo, o filtro, a ordem e o
  # next_follow_up_id nunca revelam lembrete de conversa oculta.
  def action_follow_up_join
    retornos = Crm::FollowUp.unscoped.retorno_visivel(follow_up_visibility_sql)
                            .where(account_id: @account.id).where.not(card_id: nil)
                            .group(:card_id).select('crm_follow_ups.card_id, MIN(crm_follow_ups.due_at) AS em')
    "LEFT JOIN (#{retornos.to_sql}) acao_retorno ON acao_retorno.card_id = crm_cards.id"
  end

  # Quem vê todas as conversas da conta (Crm::Conversations::Visibility#all_conversations?) não paga o filtro.
  def follow_up_visibility_sql
    visible_conversation_ids_sql unless @conversation_visibility.all_conversations?
  end

  def nobody_cares_sql
    inbox_bot = 'EXISTS (SELECT 1 FROM agent_bot_inboxes acao_robo ' \
                "WHERE acao_robo.inbox_id = COALESCE(#{CONVERSATION}.inbox_id, crm_cards.inbox_id) " \
                "AND acao_robo.status = #{AgentBotInbox.statuses[:active]})"
    "crm_cards.owner_id IS NULL AND (crm_cards.conversation_id IS NULL OR #{visible_action_conversation_sql}) " \
      "AND NOT (#{human_responsible_sql(CONVERSATION)}) AND NOT (#{bot_responsible_sql(CONVERSATION, inbox_bot)})"
  end

  # A conversa principal é visível? Uma junção só com os ids visíveis (um hash por consulta), em vez de um IN em cada
  # ponto do CASE, do "Só meus" e do filtro. Quem vê todas as conversas da conta não paga a junção: a conversa principal
  # já vem da conta pelo JOIN.
  def action_visibility_join
    "LEFT JOIN (#{visible_conversation_ids_sql}) #{VISIBLE} ON #{VISIBLE}.id = crm_cards.conversation_id"
  end

  def visible_action_conversation_sql
    return "#{CONVERSATION}.id IS NOT NULL" if @conversation_visibility.all_conversations?

    "#{VISIBLE}.id IS NOT NULL"
  end

  # Prazo de SLA no relógio corrido (o selo do card usa o calendário de expediente): só ordena dentro de "esperando".
  def sla_order?
    @account&.feature_enabled?('sla')
  end

  def sla_order_sql
    # AppliedSla.sla_statuses: active 0, active_with_misses 3 (o modelo mora no enterprise/).
    active = '0, 3'
    <<~SQL.squish
      CASE WHEN acao.grupo = 1 THEN (
        SELECT MIN(LEAST(
          CASE WHEN #{CONVERSATION}.first_reply_created_at IS NULL
            THEN #{CONVERSATION}.created_at + sla_policies.first_response_time_threshold * INTERVAL '1 second' END,
          #{CONVERSATION}.waiting_since + sla_policies.next_response_time_threshold * INTERVAL '1 second'))
        FROM applied_slas INNER JOIN sla_policies ON sla_policies.id = applied_slas.sla_policy_id
        WHERE applied_slas.conversation_id = #{CONVERSATION}.id AND applied_slas.sla_status IN (#{active})
      ) END
    SQL
  end

  def action_group_param
    return @action_group_param if defined?(@action_group_param)

    @action_group_param = KEYS.key(@params[:action_group].to_s)
  end

  def end_of_today
    @end_of_today ||= Crm::Timezone::Resolver.new(account: @account).zone_or_default.now.end_of_day
  end

  def boolean_param(key)
    ActiveModel::Type::Boolean.new.cast(@params[key]) == true
  end
end

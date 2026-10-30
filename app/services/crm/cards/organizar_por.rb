# Lista nova, "Mais → Organizar por" (#2379). Além do padrão (sort=acao, Crm::Cards::ActionGroups), seis ordens:
#   etapa      — pela posição da etapa no funil; a tela separa em grupos (summaries?group_by=stage)
#   quem_cuida — por quem cuida, a mesma regra da linha (Crm::Card#current_responsible, com a conversa oculta tratada
#                como Crm::Cards::PayloadBuilder.responsible_without_conversation_agent); a tela separa em grupos
#                (summaries?group_by=quem_cuida)
#   retorno    — o retorno da pessoa mais perto (o mesmo da situação da linha), sem retorno no fim
#   valor      — maior valor primeiro; sem `sales_value_view` (#2075), vale o padrão
#   parado     — sem mensagem e sem mudar de etapa há mais tempo (STALE_SQL, o critério do grupo "parado")
#   nome       — o nome que a linha mostra: o do contato, senão o título do card
# Todas passam pelos JOINs de ActionGroups: a linha leva o grupo de ação (a situação e a ação da linha dependem dele).
# Dentro de cada etapa ou pessoa, o que fazer primeiro (a ordem de sort=acao); o desempate final é o id, para a página
# seguinte continuar de onde parou, sem grupo pela metade.
#
# Incluído no Crm::Cards::FilterQuery, depois de ActionGroups (usa CONVERSATION e a visibilidade de lá).
module Crm::Cards::OrganizarPor
  SORTS = %w[etapa quem_cuida retorno valor parado nome].freeze
  QUEM_CUIDA = 'quem_cuida'.freeze
  # tipo 'agent' | 'bot' | NULL (ninguém cuida) e o id da pessoa ou do robô.
  QUEM = 'acao_quem'.freeze
  QUEM_TIPO = "#{QUEM}.tipo".freeze
  QUEM_ID = "#{QUEM}.id".freeze

  def self.sort?(params)
    SORTS.include?(params[:sort].to_s)
  end

  def self.group_by_quem_cuida?(params)
    params[:group_by].to_s == QUEM_CUIDA
  end

  # A página da Lista nova: o grupo de ação e o retorno da pessoa vêm em cada linha.
  def self.lista_nova?(params)
    Crm::Cards::ActionGroups.sort?(params) || sort?(params)
  end

  private

  def organizar_needed?
    Crm::Cards::OrganizarPor.sort?(@params) || Crm::Cards::OrganizarPor.group_by_quem_cuida?(@params)
  end

  def apply_organizar_joins(cards)
    sort = @params[:sort].to_s
    cards = cards.joins(quem_cuida_lateral) if sort == QUEM_CUIDA || Crm::Cards::OrganizarPor.group_by_quem_cuida?(@params)
    cards = cards.joins(quem_cuida_names_join) if sort == QUEM_CUIDA
    cards = cards.joins(stage_order_join) if sort == 'etapa'
    cards = cards.joins(contact_name_join) if sort == 'nome'
    cards
  end

  # Lista nova: o padrão (sort=acao) ou a ordem de "Organizar por".
  def apply_lista_nova_sort(cards)
    Crm::Cards::ActionGroups.sort?(@params) ? apply_action_sort(cards) : apply_organizar_sort(cards)
  end

  def apply_organizar_sort(cards)
    first = organizar_terms
    return apply_action_sort(cards) if first.nil?

    cards.reorder(*first, *action_sort_terms)
  end

  # nil: a ordem pedida não vale para quem pede (valor sem `sales_value_view`) e fica o padrão.
  def organizar_terms
    case @params[:sort].to_s
    when 'etapa' then [asc('acao_etapa.position'), asc('crm_cards.stage_id')]
    when QUEM_CUIDA then quem_cuida_terms
    when 'retorno' then [asc('acao.retorno_em').nulls_last]
    when 'valor' then value_terms
    when 'parado' then [asc(Crm::Cards::SharedFilters::STALE_SQL).nulls_first]
    when 'nome' then [asc("LOWER(COALESCE(NULLIF(acao_contato.name, ''), crm_cards.title))")]
    end
  end

  def value_terms
    return unless Crm::ValorDeVenda.ve?(@account_user)

    [Arel::Nodes::Descending.new(Arel.sql('crm_cards.value_cents')).nulls_last]
  end

  # Pessoas, depois robôs, por nome; ninguém cuidando no fim. Tipo e id desempatam dois nomes iguais (grupo inteiro).
  def quem_cuida_terms
    [asc("CASE #{QUEM_TIPO} WHEN 'agent' THEN 0 WHEN 'bot' THEN 1 ELSE 2 END"),
     asc('LOWER(COALESCE(acao_quem_pessoa.name, acao_quem_robo.name))').nulls_last,
     asc(QUEM_TIPO), asc(QUEM_ID)]
  end

  # Quem cuida, como Crm::Card#current_responsible: o dono; senão a pessoa da conversa principal, só se quem lê vê essa
  # conversa (oculta: o nome de quem atende não sai, PayloadBuilder#sanitize_hidden_conversation!); senão o robô da
  # conversa (#1377) ou o robô ativo da caixa (Crm::Card#responsible_agent_bot); senão ninguém.
  def quem_cuida_lateral
    # O robô da conversa só se ainda existe (ai_assignee apagado é nil no Ruby e cai para o robô da caixa).
    conversation_bot = '(SELECT agent_bots.id FROM agent_bots WHERE agent_bots.id = ' \
                       "#{Crm::Cards::ActionGroups::CONVERSATION}.assignee_agent_bot_id AND " \
                       "COALESCE(#{Crm::Cards::ActionGroups::CONVERSATION}.ai_assignee_type, '') = 'AgentBot')"
    # O robô da caixa como o has_one :agent_bot_inbox (InboxBotStatus, #2298): a linha ativa de menor id; robô apagado é nil.
    inbox_bot = '(SELECT agent_bots.id FROM agent_bot_inboxes LEFT JOIN agent_bots ON agent_bots.id = agent_bot_inboxes.agent_bot_id ' \
                "WHERE agent_bot_inboxes.inbox_id = COALESCE(#{Crm::Cards::ActionGroups::CONVERSATION}.inbox_id, crm_cards.inbox_id) " \
                "AND agent_bot_inboxes.status = #{AgentBotInbox.statuses[:active]} ORDER BY agent_bot_inboxes.id LIMIT 1)"
    <<~SQL.squish
      LEFT JOIN LATERAL (
        SELECT CASE WHEN quem.pessoa IS NOT NULL THEN 'agent' WHEN quem.robo IS NOT NULL THEN 'bot' END AS tipo,
          COALESCE(quem.pessoa, quem.robo) AS id
        FROM (SELECT
          COALESCE(crm_cards.owner_id,
            CASE WHEN #{visible_action_conversation_sql} THEN #{Crm::Cards::ActionGroups::CONVERSATION}.assignee_id END) AS pessoa,
          COALESCE(#{conversation_bot}, #{inbox_bot}) AS robo) quem
      ) #{QUEM} ON TRUE
    SQL
  end

  def quem_cuida_names_join
    "LEFT JOIN users acao_quem_pessoa ON #{QUEM_TIPO} = 'agent' AND acao_quem_pessoa.id = #{QUEM_ID} " \
      "LEFT JOIN agent_bots acao_quem_robo ON #{QUEM_TIPO} = 'bot' AND acao_quem_robo.id = #{QUEM_ID}"
  end

  # Alias próprio: o includes(:stage) da base não pode virar eager_load por causa deste JOIN.
  def stage_order_join
    'LEFT JOIN crm_pipeline_stages acao_etapa ON acao_etapa.id = crm_cards.stage_id'
  end

  def contact_name_join
    'LEFT JOIN contacts acao_contato ON acao_contato.id = crm_cards.contact_id AND acao_contato.account_id = crm_cards.account_id'
  end
end

# Shared filter predicates for CRM cards so the board (Crm::Kanban::BoardPayloadBuilder)
# and the list (Crm::Cards::FilterQuery) agree on every server-side filter. Adding a
# filter to only one path re-creates the historical "Status" board/list divergence, so
# every new param MUST be honored here and mirrored client-side in cardMatchesFilters
# (crmKanban.js) OR force a refetch-on-realtime. Per-filter realtime contract:
#   * client-predicate (mirrored in cardMatchesFilters): stage_ids, value_min/value_max,
#     score_min/score_max,
#     stale_days, standalone, team_id, priority, inbox_id, owner_id, search, follow_up.
#   * server-only + refetch-on-realtime (cannot be derived from a single upsert payload):
#     responsible_kind (bot/none rely on the active inbox bot join + conversation assignee),
#     ai_pending (the pending-suggestion set is computed per board load) and label_ids
#     (matches taggings of the primary conversation, source of truth for labels) and campaign_source_ids (without
#     meta_ads_view the ad touch comes without source_id, #2271).
module Crm::Cards::SharedFilters
  include Crm::Cards::CompanyFilters

  RESPONSIBLE_KINDS = %w[agent bot none].freeze
  # Parado: sem mensagem real e sem mudar de etapa (GREATEST ignora o NULL). Também é o grupo "Parados" da Lista nova.
  STALE_SQL = 'GREATEST(crm_cards.last_message_at, crm_cards.entered_stage_at)'.freeze
  # Caixas com robô ativo, uma linha por caixa: sem índice único por inbox_id (#2298), duas linhas ativas na mesma
  # caixa repetiam o card na Lista e nas contas do resumo. Mesma subconsulta do ActionGroups::ACTIVE_BOT_JOIN.
  RESPONSIBLE_BOT = 'responsavel_robo'.freeze
  RESPONSIBLE_BOT_JOIN = 'LEFT JOIN (SELECT DISTINCT agent_bot_inboxes.inbox_id FROM agent_bot_inboxes ' \
                         "WHERE agent_bot_inboxes.status = #{AgentBotInbox.statuses[:active]}) " \
                         "#{RESPONSIBLE_BOT} ON #{RESPONSIBLE_BOT}.inbox_id = " \
                         'COALESCE(conversations.inbox_id, crm_cards.inbox_id)'.freeze

  def apply_stage_ids_filter(cards)
    ids = parse_stage_ids
    return cards if ids.blank?

    cards.where(stage_id: ids)
  end

  def apply_value_range_filter(cards)
    cards = cards.where('crm_cards.value_cents >= ?', value_cents_param(:value_min)) if value_cents_param(:value_min)
    cards = cards.where('crm_cards.value_cents <= ?', value_cents_param(:value_max)) if value_cents_param(:value_max)
    cards
  end

  def apply_score_range_filter(cards)
    minimum = score_filter_value(:score_min)
    maximum = score_filter_value(:score_max)
    cards = cards.where('crm_cards.score >= ?', minimum) if minimum
    cards = cards.where('crm_cards.score <= ?', maximum) if maximum
    cards
  end

  # No real message AND no stage movement in N days (GREATEST is NULL-safe).
  def apply_stale_filter(cards)
    days = @params[:stale_days].presence&.to_i
    return cards if days.blank? || days <= 0

    cards.where("#{STALE_SQL} IS NULL OR #{STALE_SQL} < ?", days.days.ago)
  end

  def apply_team_filter(cards)
    return cards if @params[:team_id].blank?

    cards.where(team_id: @params[:team_id])
  end

  # Sugestão de etapa (#2150): sem crm_manage_ai o filtro é ignorado, porque revelaria quais cards têm sugestão.
  def apply_ai_pending_filter(cards)
    return cards unless ActiveModel::Type::Boolean.new.cast(@params[:ai_pending])
    return cards unless Crm::SugestaoDeEtapa.le?(@account_user)

    cards.where(id: Crm::AiStageSuggestion.where(status: :pending).select(:card_id))
  end

  # responsible_kind maps the realtime "responsible" descriptor to SQL:
  #   agent -> a human is responsible (linked conversation assignee, or owner when standalone)
  #   bot   -> no human responsible, but the resolved inbox has an active agent bot
  #   none  -> no human responsible and no active agent bot
  def apply_responsible_filter(cards)
    kind = @params[:responsible_kind].to_s
    return cards unless RESPONSIBLE_KINDS.include?(kind)

    scoped = cards
             .joins('LEFT JOIN conversations ON conversations.id = crm_cards.conversation_id')
             .joins(RESPONSIBLE_BOT_JOIN)
    case kind
    when 'agent'
      scoped.where(human_responsible_sql)
    when 'bot'
      scoped.where("NOT (#{human_responsible_sql})").where(bot_responsible_sql)
    when 'none'
      scoped.where("NOT (#{human_responsible_sql})").where.not(bot_responsible_sql)
    end
  end

  # Campaign filter (CTWA multi-touch): campaign_source_ids is a csv of ad source_ids
  # with OR semantics — a card matches when ANY touch of ANY linked conversation
  # (crm_card_conversations OR the direct primary conversation_id) hits any of the ids.
  # It probes the `campaign_source_ids` jsonb-array mirror rendered as text with a
  # quoted token (ILIKE '%"<id>"%'), so substrings of other ids never false-positive
  # and the trigram index on the mirror is used. Standalone cards (no conversations)
  # are always excluded.
  def apply_campaign_filter(cards)
    source_ids = parse_campaign_source_ids
    return cards if source_ids.blank?

    tokens = source_ids.map { |source_id| "%\"#{ActiveRecord::Base.sanitize_sql_like(source_id)}\"%" }
    mirror_predicates = tokens.map { "conversations.additional_attributes ->> 'campaign_source_ids' ILIKE ?" }
    cards.where(<<~SQL.squish, *tokens)
      EXISTS (
        SELECT 1 FROM conversations
        WHERE conversations.account_id = crm_cards.account_id
          AND conversations.id IN (#{visible_conversation_ids_sql})
          AND (conversations.id = crm_cards.conversation_id
               OR conversations.id IN (SELECT ccc.conversation_id FROM crm_card_conversations ccc WHERE ccc.card_id = crm_cards.id))
          AND (#{mirror_predicates.join(' OR ')})
      )
    SQL
  end

  # Label filter: label_ids is a csv of Label ids (OR semantics) matched against the
  # PRIMARY conversation OR the linked CONTACT (mirrors the card `labels` +
  # `contact_labels` payloads — campaign import labels only ever live on the
  # contact, never synced onto the conversation). EXISTS keeps one row per card.
  def apply_label_filter(cards)
    label_ids = parse_label_ids
    return cards if label_ids.blank?

    predicate = "(crm_cards.conversation_id IN (#{visible_conversation_ids_sql}) AND " \
                "#{label_exists_sql('Conversation', 'crm_cards.conversation_id')}) OR " \
                "#{label_exists_sql('Contact', 'crm_cards.contact_id')}"
    cards.where(predicate, label_ids, label_ids)
  end

  # EXISTS fragment matching a taggable against an account-scoped Label id list,
  # via the tags.name == labels.title bridge (Chatwoot labels are acts-as-taggable).
  def label_exists_sql(taggable_type, taggable_id_column)
    'EXISTS (SELECT 1 FROM taggings INNER JOIN tags ON tags.id = taggings.tag_id ' \
      'INNER JOIN labels ON labels.title = tags.name AND labels.account_id = crm_cards.account_id ' \
      "WHERE taggings.taggable_type = '#{taggable_type}' AND taggings.context = 'labels' " \
      "AND taggings.taggable_id = #{taggable_id_column} AND labels.id IN (?))"
  end

  private

  # Authorization is applied before rows, pagination, sums and counts are built.
  # Required caller context prevents a filter from revealing hidden-chat metadata.
  def visible_conversation_ids_sql
    @visible_conversation_ids_sql ||= @conversation_visibility.scope(Conversation.all).select(:id).to_sql
  end

  # A human is responsible when the linked conversation has an assignee, or (for cards
  # without a linked conversation) when an owner is set. Mirrors Crm::Card#responsible_descriptor.
  # `conversation` é o nome da conversa principal na consulta (a Lista nova, #2283, junta com outro nome).
  def human_responsible_sql(conversation = 'conversations')
    "(crm_cards.conversation_id IS NOT NULL AND #{conversation}.assignee_id IS NOT NULL) OR " \
      '(crm_cards.conversation_id IS NULL AND crm_cards.owner_id IS NOT NULL)'
  end

  # Robô responsável: o atribuído à conversa (#1377) ou o robô ativo da caixa. Mirrors Crm::Card#responsible_agent_bot.
  # `inbox_bot` diz como a consulta acha o robô ativo da caixa (aqui, pelo RESPONSIBLE_BOT_JOIN).
  def bot_responsible_sql(conversation = 'conversations', inbox_bot = "#{RESPONSIBLE_BOT}.inbox_id IS NOT NULL")
    "(#{conversation}.assignee_agent_bot_id IS NOT NULL AND COALESCE(#{conversation}.ai_assignee_type, '') = 'AgentBot') " \
      "OR #{inbox_bot}"
  end

  def parse_stage_ids
    Array(@params[:stage_ids].presence || @params[:stage_id].presence)
      .flat_map { |stage_id| stage_id.to_s.split(',') }
      .filter_map { |stage_id| Integer(stage_id, exception: false) }
      .uniq
  end

  def parse_label_ids
    Array(@params[:label_ids].presence)
      .flat_map { |label_id| label_id.to_s.split(',') }
      .filter_map { |label_id| Integer(label_id, exception: false) }
      .uniq
  end

  # source_ids are opaque Meta ad ids — keep them as strings (never Integer-cast).
  # Anúncio de origem (#2271): para a função personalizada sem meta_ads_view, os ids de anúncio saem do filtro (filtrar
  # por eles revelaria qual card veio de qual anúncio); os de divulgação (WhatsApp, e-mail, SMS) continuam filtrando.
  # Só com ids de anúncio, o filtro fica vazio e é ignorado, como o filtro por valor (#2075).
  # O robô filtra por tudo; sem identidade, não (Crm::AnuncioDeOrigem.ve_no_contexto?).
  def parse_campaign_source_ids
    ids = Array(@params[:campaign_source_ids].presence)
          .flat_map { |source_id| source_id.to_s.split(',') }
          .map(&:strip)
          .reject(&:blank?)
          .uniq
    @conversation_visibility.anuncio_visivel? ? ids : sem_ids_de_anuncio(ids)
  end

  def sem_ids_de_anuncio(ids)
    account = @account_user&.account || @account
    account ? ids - Crm::AnuncioDeOrigem::Ids.de_anuncio(account, ids) : []
  end

  # Valor de venda (#2075): sem `sales_value_view` o filtro por valor é ignorado, porque revelaria o valor. Também vale
  # para a visão salva, que manda os mesmos parâmetros. @account_user vem do quadro e da lista.
  def value_cents_param(key)
    return unless Crm::ValorDeVenda.ve?(@account_user)

    raw = @params[key]
    return if raw.blank?

    Integer(raw, exception: false)
  end

  def score_filter_value(key)
    raw = @params[key]
    return unless raw.is_a?(String) || raw.is_a?(Integer)

    value = Integer(raw, exception: false)
    value if value&.between?(0, 100)
  end
end

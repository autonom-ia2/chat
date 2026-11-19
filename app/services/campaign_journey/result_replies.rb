# "Responderam" of a campaign result (#1007, PRD §6.5 and §6.10): the contacts whose conversation got
# the campaign mark of #1002 (a message received within 72h of the send, CampaignJourney::ReplyMarker).
# Read from the conversations' mark mirror `campaign_source_ids`, the same text probe the Kanban
# campaign filter uses (Crm::Cards::SharedFilters#apply_campaign_filter), so the trigram index on the
# mirror serves both. A contact counts once per campaign, whatever the number of conversations.
#
# "Viraram cards no CRM" (Gestão): CRM cards linked to a conversation marked by the campaign, as the
# primary conversation or through crm_card_conversations — the cards the Kanban shows when filtered by
# that campaign. `won` is the part of them that closed as a sale: won (archived after won included) or, on a renewal
# of the policy portfolio, resolved with the new policy already in (the funnel of renewals may not count as sale; the
# new policy is the proof it renewed — Carteira::Renovacao::Desfecho reads resolved as "renovou"). A resolved card
# without a new policy is a service closing, never revenue (Crm::Cards::Outcome), and stays out.
#
# `won_value` (#3063, decisão do Rodrigo 19/11: o prêmio, não a comissão): the money of those cards, per currency,
# biggest first. A renewal card whose new policy already arrived (carteira_apolices: the previous policy holds the
# card in `crm_card_id`, the new one points back through `apolice_anterior_id`) counts the premium of the new policy;
# a cancelled new policy, one without a premium, or a card with no policy counts the card value. The new policy often
# arrives days after the card is won, so the number can grow afterwards. nil when the reader does not see sales values
# (Crm::ValorDeVenda); the counts stay. Access by funnel (#1148) leaves the funnels the reader does not see out, like
# the CRM reports.
class CampaignJourney::ResultReplies
  CAMPAIGN_MARK_PROBE = '%"campaign:%'.freeze
  MARK_JOIN = "CROSS JOIN LATERAL jsonb_array_elements_text(conversations.additional_attributes -> 'campaign_source_ids') " \
              'AS campaign_mark(source_id)'.freeze
  # Only one new policy per previous one (Carteira::Renovacao::ApoliceNova); the ORDER keeps the pick stable anyway.
  RENEWAL_PREMIUM_JOIN = <<~SQL.squish.freeze
    LEFT JOIN LATERAL (
      SELECT nova.valor_centavos FROM carteira_apolices anterior
      INNER JOIN carteira_apolices nova ON nova.apolice_anterior_id = anterior.id AND nova.account_id = anterior.account_id
      WHERE anterior.crm_card_id = crm_cards.id AND anterior.account_id = crm_cards.account_id
        AND nova.cancelado_em IS NULL AND nova.valor_centavos IS NOT NULL
      ORDER BY nova.id DESC
      LIMIT 1
    ) renewal_premium ON TRUE
  SQL
  STATUS = Crm::Card.statuses
  ARCHIVED_AS = lambda { |desfecho|
    "(crm_cards.status = #{STATUS.fetch('archived')} AND crm_cards.metadata ->> '#{Crm::Card::DESFECHO_ARQUIVADO}' = '#{desfecho}')"
  }
  CLOSED_SALE = "(crm_cards.status = #{STATUS.fetch('won')} OR #{ARCHIVED_AS.call('won')} OR " \
                "(renewal_premium.valor_centavos IS NOT NULL AND (crm_cards.status = #{STATUS.fetch('resolved')} OR " \
                "#{ARCHIVED_AS.call('resolved')})))".freeze
  # The premium of a policy is always in reais; the card keeps its own currency (free text: trimmed and upper-cased).
  CURRENCY = "CASE WHEN renewal_premium.valor_centavos IS NULL THEN UPPER(COALESCE(NULLIF(TRIM(crm_cards.currency), ''), 'BRL')) " \
             "ELSE 'BRL' END".freeze
  CENTS = 'COALESCE(renewal_premium.valor_centavos, crm_cards.value_cents)'.freeze
  TOTALS = [CURRENCY, 'COUNT(*)', "COUNT(*) FILTER (WHERE #{CLOSED_SALE})",
            "COALESCE(SUM(#{CENTS}) FILTER (WHERE #{CLOSED_SALE}), 0)"].map { |sql| Arel.sql(sql) }.freeze

  def initialize(account, source_ids)
    @account = account
    @source_ids = Array(source_ids).compact.uniq
  end

  # { source_id => contacts that replied }
  def counts
    return {} if @source_ids.empty?

    marked.group('campaign_mark.source_id').distinct.count(:contact_id)
  end

  def contact_ids
    return [] if @source_ids.empty?

    marked.distinct.pluck(:contact_id)
  end

  # { contact_id => display_id } of the latest marked conversation the user can open.
  def conversations_by_contact(contact_ids, visible_conversations)
    return {} if @source_ids.empty? || contact_ids.blank?

    marked.where(contact_id: contact_ids, id: visible_conversations.select(:id))
          .order(:created_at).pluck(:contact_id, :display_id).to_h
  end

  # Latest marked conversation per contact (id, display_id, contact_id), newest first.
  def latest_conversations
    return Conversation.none if @source_ids.empty?

    ids = marked.group(:contact_id).maximum(:id).values
    @account.conversations.where(id: ids).order(id: :desc)
  end

  # What the campaign turned into in the CRM for this reader (the counts for who reads campaigns; the money only with
  # sales values; only the funnels the reader sees in the reports).
  def deals_for(user:, account_user:)
    visible = Crm::Access::VisiblePipelines.new(user: user, account: @account, account_user: account_user)
    deals(with_value: Crm::ValorDeVenda.ve?(account_user), pipeline_ids: (visible.report_ids if visible.restricted?))
  end

  # pipeline_ids: nil = every funnel. One query: per currency, the cards, the closed sales and their money.
  def deals(with_value: false, pipeline_ids: nil)
    return { cards: 0, won: 0, won_value: with_value ? [] : nil } if @source_ids.empty?

    rows = campaign_cards(pipeline_ids).joins(RENEWAL_PREMIUM_JOIN).group(TOTALS.first).pluck(*TOTALS)
    { cards: rows.sum { |row| row[1] }, won: rows.sum { |row| row[2] }, won_value: with_value ? won_value(rows) : nil }
  end

  private

  def campaign_cards(pipeline_ids)
    conversation_ids = marked.select(:id)
    linked = Crm::CardConversation.where(account_id: @account.id, conversation_id: conversation_ids).select(:card_id)
    account_cards = Crm::Card.where(account_id: @account.id)
    account_cards = account_cards.where(pipeline_id: pipeline_ids) unless pipeline_ids.nil?
    account_cards.where(conversation_id: conversation_ids).or(account_cards.where(id: linked))
  end

  # [{ currency: 'BRL', cents: 120_000 }], biggest first; currencies with no money are left out.
  def won_value(rows)
    rows.map { |currency, _cards, _won, cents| { currency: currency, cents: cents.to_i } }
        .select { |item| item[:cents].positive? }
        .sort_by { |item| -item[:cents] }
  end

  def marked
    @account.conversations
            .where("conversations.additional_attributes ->> 'campaign_source_ids' ILIKE ?", CAMPAIGN_MARK_PROBE)
            .joins(MARK_JOIN)
            .where(campaign_mark: { source_id: @source_ids })
  end
end

# "Responderam" of a campaign result (#1007, PRD §6.5 and §6.10): the contacts whose conversation got
# the campaign mark of #1002 (a message received within 72h of the send, CampaignJourney::ReplyMarker).
# Read from the conversations' mark mirror `campaign_source_ids`, the same text probe the Kanban
# campaign filter uses (Crm::Cards::SharedFilters#apply_campaign_filter), so the trigram index on the
# mirror serves both. A contact counts once per campaign, whatever the number of conversations.
#
# "Viraram cards no CRM" (Gestão): CRM cards linked to a conversation marked by the campaign, as the
# primary conversation or through crm_card_conversations — the cards the Kanban shows when filtered by
# that campaign. `won` is the part of them already closed as won or resolved (the same reading
# Carteira::Renovacao::Desfecho does for "renovou"; archived after closing still counts).
#
# `won_value` (#3063, decisão do Rodrigo 19/11: o prêmio, não a comissão): the R$ of those cards, per currency,
# biggest first. A renewal card whose new policy already arrived (carteira_apolices: the previous policy holds the
# card in `crm_card_id`, the new one points back through `apolice_anterior_id`) counts the premium of the new policy;
# a cancelled new policy, one without a premium, or a card with no policy counts the card value. The new policy often
# arrives days after the card is won, so the number can grow afterwards. nil when the reader does not see sales values
# (Crm::ValorDeVenda); the counts stay.
class CampaignJourney::ResultReplies
  CAMPAIGN_MARK_PROBE = '%"campaign:%'.freeze
  MARK_JOIN = "CROSS JOIN LATERAL jsonb_array_elements_text(conversations.additional_attributes -> 'campaign_source_ids') " \
              'AS campaign_mark(source_id)'.freeze
  WON = %i[won resolved].freeze
  # Only one new policy per previous one (Carteira::Renovacao::ApoliceNova); LIMIT 1 keeps one row per card anyway.
  RENEWAL_PREMIUM_JOIN = <<~SQL.squish.freeze
    LEFT JOIN LATERAL (
      SELECT nova.valor_centavos FROM carteira_apolices anterior
      INNER JOIN carteira_apolices nova ON nova.apolice_anterior_id = anterior.id AND nova.account_id = anterior.account_id
      WHERE anterior.crm_card_id = crm_cards.id AND anterior.account_id = crm_cards.account_id
        AND nova.cancelado_em IS NULL AND nova.valor_centavos IS NOT NULL
      LIMIT 1
    ) renewal_premium ON TRUE
  SQL
  # The premium of a policy is always in reais; the card keeps its own currency.
  WON_VALUE_CURRENCY = "CASE WHEN renewal_premium.valor_centavos IS NULL THEN COALESCE(NULLIF(crm_cards.currency, ''), 'BRL') " \
                       "ELSE 'BRL' END".freeze
  WON_VALUE_CENTS = 'COALESCE(renewal_premium.valor_centavos, crm_cards.value_cents)'.freeze

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

  def deals(with_value: false)
    return { cards: 0, won: 0, won_value: with_value ? [] : nil } if @source_ids.empty?

    conversation_ids = marked.select(:id)
    linked = Crm::CardConversation.where(account_id: @account.id, conversation_id: conversation_ids).select(:card_id)
    account_cards = Crm::Card.where(account_id: @account.id)
    cards = account_cards.where(conversation_id: conversation_ids).or(account_cards.where(id: linked))
    won = cards.com_desfecho(*WON)
    { cards: cards.count, won: won.count, won_value: with_value ? won_value(won) : nil }
  end

  private

  # [{ currency: 'BRL', cents: 120_000 }], biggest first; currencies that add up to zero are left out.
  def won_value(won)
    won.joins(RENEWAL_PREMIUM_JOIN).group(Arel.sql(WON_VALUE_CURRENCY)).sum(Arel.sql(WON_VALUE_CENTS))
       .select { |_currency, cents| cents.positive? }
       .sort_by { |_currency, cents| -cents }
       .map { |currency, cents| { currency: currency, cents: cents.to_i } }
  end

  def marked
    @account.conversations
            .where("conversations.additional_attributes ->> 'campaign_source_ids' ILIKE ?", CAMPAIGN_MARK_PROBE)
            .joins(MARK_JOIN)
            .where(campaign_mark: { source_id: @source_ids })
  end
end

# Resultado por campanha dos links de página (#1011), para a tela Links e QR codes:
# cliques, conversas e vendas ganhas de cada campanha (chave `campaign_key` do clique).
#
# `won_cards` conta cards ganhos cuja conversa principal está entre as conversas atribuídas
# aos cliques daquela campanha; o valor sai somado por moeda, em centavos. Poucas consultas
# agregadas para todos os links de uma vez — a tela lista vários links por conta.
#
# Receita (`won_cards`, `won_value_by_currency`) é dado financeiro somado de todas as caixas:
# só sai com `include_revenue: true`, que o controller dá apenas a administradores (regra do
# projeto: financeiro nunca se delega por função personalizada).
class Ctwa::TrackedLinkCampaigns
  KEY_SQL = "COALESCE(NULLIF(ctwa_tracked_link_clicks.campaign_key, ''), 'none')".freeze

  def self.for_links(account, links, include_revenue: false)
    new(account, links, include_revenue: include_revenue).perform
  end

  def initialize(account, links, include_revenue: false)
    @account = account
    @link_ids = links.map(&:id)
    @include_revenue = include_revenue
  end

  # { link_id => [{ campaign_key:, name:, clicks:, last_clicked_at:, conversations:, won_cards:, won_value_by_currency: }] }
  # (as duas últimas só com include_revenue)
  def perform
    return {} if @link_ids.empty?

    conversations = conversations_by_campaign
    won = @include_revenue ? won_cards_by_conversation(conversations.values.flatten.uniq) : nil
    names = names_by_campaign

    click_counts.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(link_id, key, clicks, last_clicked_at), result|
      conversation_ids = conversations.fetch([link_id, key], [])
      row = campaign_row(key, names[[link_id, key]], clicks, conversation_ids, won)
      # Quando chegou o último clique da campanha: com isso a tela diz qual anúncio ficou sem o texto (#1068).
      result[link_id] << row.merge(last_clicked_at: last_clicked_at&.iso8601)
    end
  end

  private

  def campaign_row(key, name, clicks, conversation_ids, won)
    row = { campaign_key: key, name: name, clicks: clicks, conversations: conversation_ids.size }
    return row if won.nil?

    cards = conversation_ids.flat_map { |conversation_id| won.fetch(conversation_id, []) }.uniq { |card| card[:id] }
    row.merge(won_cards: cards.size, won_value_by_currency: value_by_currency(cards))
  end

  def value_by_currency(cards)
    cards.each_with_object(Hash.new(0)) do |card, totals|
      totals[card[:currency].presence || 'BRL'] += card[:value_cents].to_i
    end
  end

  def clicks
    Ctwa::TrackedLinkClick.where(account_id: @account.id, tracked_link_id: @link_ids)
  end

  def click_counts
    clicks.group(:tracked_link_id, Arel.sql(KEY_SQL))
          .order(Arel.sql('COUNT(*) DESC'), Arel.sql(KEY_SQL))
          .pluck(:tracked_link_id, Arel.sql(KEY_SQL), Arel.sql('COUNT(*)'), Arel.sql('MAX(ctwa_tracked_link_clicks.created_at)'))
  end

  # Nome = utm_campaign mais recente da chave.
  def names_by_campaign
    rows = clicks.where("COALESCE(ctwa_tracked_link_clicks.params ->> 'utm_campaign', '') <> ''")
                 .select(Arel.sql("DISTINCT ON (tracked_link_id, #{KEY_SQL}) tracked_link_id, #{KEY_SQL} AS key, " \
                                  "params ->> 'utm_campaign' AS name"))
                 .order(Arel.sql("tracked_link_id, #{KEY_SQL}, ctwa_tracked_link_clicks.created_at DESC"))
    rows.to_h { |row| [[row.tracked_link_id, row['key']], row['name']] }
  end

  def conversations_by_campaign
    clicks.where.not(conversation_id: nil).distinct
          .pluck(:tracked_link_id, Arel.sql(KEY_SQL), :conversation_id)
          .each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(link_id, key, conversation_id), result|
      result[[link_id, key]] << conversation_id
    end
  end

  def won_cards_by_conversation(conversation_ids)
    return {} if conversation_ids.empty?

    Crm::Card.where(account_id: @account.id, status: :won, conversation_id: conversation_ids)
             .pluck(:id, :conversation_id, :currency, :value_cents)
             .group_by { |row| row[1] }
             .transform_values { |rows| rows.map { |id, _conv, currency, cents| { id: id, currency: currency, value_cents: cents } } }
  end
end

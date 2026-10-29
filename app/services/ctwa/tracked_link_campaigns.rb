# Resultado por campanha dos links de página (#1011), para a tela Links e QR codes:
# cliques, conversas e vendas ganhas de cada campanha (chave `campaign_key` do clique).
#
# `won_cards` conta cards ganhos cuja conversa principal está entre as conversas atribuídas
# aos cliques daquela campanha; o valor sai somado por moeda, em centavos. Poucas consultas
# agregadas para todos os links de uma vez — a tela lista vários links por conta.
#
# Vendas (#2075, lote 13): `won_cards` e o valor contam só os cards que a pessoa vê no CRM
# (Crm::Cards::VisibleScopeQuery: caixa, "só as atribuídas" e funil; o administrador vê todos).
# A contagem sai para quem vê a tela; `won_value_by_currency` só com o Crm::ValorDeVenda.ve?
# (sem a chave, a chave do valor nem vem, e a tela não mostra a coluna).
class Ctwa::TrackedLinkCampaigns
  KEY_SQL = "COALESCE(NULLIF(ctwa_tracked_link_clicks.campaign_key, ''), 'none')".freeze
  # Clique que veio de anúncio da Meta (#2338), pela regra da origem da conversa (Ctwa::CampaignBuilder#source_for):
  # gclid e ttclid vêm antes; depois, fbclid ou UTMs pagas da Meta (o iPhone pode tirar o fbclid). O cookie fbc não
  # entra: fica meses no navegador (visita direta contaria como anúncio) e some na retenção dos cliques. Visita direta
  # ou orgânica ao site também chega sem nome de campanha; sem isto o aviso de "clique sem nome" contava as duas.
  META_CLICK_CONDITION = ActiveRecord::Base.sanitize_sql_array(
    [
      "COALESCE(ctwa_tracked_link_clicks.params ->> 'gclid', '') = '' " \
      "AND COALESCE(ctwa_tracked_link_clicks.params ->> 'ttclid', '') = '' " \
      "AND (COALESCE(ctwa_tracked_link_clicks.params ->> 'fbclid', '') <> '' " \
      "OR (LOWER(BTRIM(ctwa_tracked_link_clicks.params ->> 'utm_source', :blank)) IN (:sources) " \
      "AND LOWER(BTRIM(ctwa_tracked_link_clicks.params ->> 'utm_medium', :blank)) IN (:mediums)))",
      { blank: " \t\n\v\f\r", sources: Ctwa::CampaignBuilder::META_UTM_SOURCES, mediums: Ctwa::CampaignBuilder::PAID_UTM_MEDIUMS }
    ]
  ).freeze

  def self.for_links(account, links, account_user:)
    new(account, links, account_user: account_user).perform
  end

  def initialize(account, links, account_user:)
    @account = account
    @link_ids = links.map(&:id)
    @account_user = account_user
    @include_value = Crm::ValorDeVenda.ve?(account_user)
  end

  # { link_id => [{ campaign_key:, name:, clicks:, meta_clicks:, last_clicked_at:, last_meta_clicked_at:, conversations:,
  #                 won_cards:, won_value_by_currency: }] }
  # (a última só com o Crm::ValorDeVenda.ve?)
  def perform
    return {} if @link_ids.empty?

    conversations = conversations_by_campaign
    won = won_cards_by_conversation(conversations.values.flatten.uniq)
    names = names_by_campaign

    click_counts.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(link_id, key, clicks, meta_clicks, last_at, last_meta_at), result|
      conversation_ids = conversations.fetch([link_id, key], [])
      row = campaign_row(key, names[[link_id, key]], { clicks: clicks, meta_clicks: meta_clicks }, conversation_ids, won)
      # Quando chegou o último clique da campanha: com isso a tela diz qual anúncio ficou sem o texto (#1068).
      result[link_id] << row.merge(last_clicked_at: last_at&.iso8601, last_meta_clicked_at: last_meta_at&.iso8601)
    end
  end

  private

  def campaign_row(key, name, counts, conversation_ids, won)
    cards = conversation_ids.flat_map { |conversation_id| won.fetch(conversation_id, []) }.uniq { |card| card[:id] }
    row = { campaign_key: key, name: name, **counts, conversations: conversation_ids.size, won_cards: cards.size }
    @include_value ? row.merge(won_value_by_currency: value_by_currency(cards)) : row
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
          .pluck(:tracked_link_id, Arel.sql(KEY_SQL), Arel.sql('COUNT(*)'), Arel.sql("COUNT(*) FILTER (WHERE #{META_CLICK_CONDITION})"),
                 Arel.sql('MAX(ctwa_tracked_link_clicks.created_at)'),
                 Arel.sql("MAX(ctwa_tracked_link_clicks.created_at) FILTER (WHERE #{META_CLICK_CONDITION})"))
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

    rows = visible_won_cards(conversation_ids).pluck(:id, :conversation_id, :currency, :value_cents)
    rows.group_by { |row| row[1] }
        .transform_values { |list| list.map { |id, _conv, currency, cents| { id: id, currency: currency, value_cents: cents } } }
  end

  def visible_won_cards(conversation_ids)
    scope = Crm::Card.where(conversation_id: conversation_ids).com_desfecho(:won)
    Crm::Cards::VisibleScopeQuery.new(scope: scope, account: @account, user: @account_user&.user, account_user: @account_user).perform
  end
end

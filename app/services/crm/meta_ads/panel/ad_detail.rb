# O anúncio por dentro (#1088, F3b): o mesmo anúncio da lista do painel, com o porquê do veredito, o dia a dia
# do período e as propostas que ele trouxe.
#
# Os números (gasto, conversas, propostas, vendas, veredito, média da conta) saem do próprio Panel::Report: a
# tela do anúncio nunca pode mostrar um número diferente do cartão em que a pessoa clicou. Anúncio sem gasto nem
# conversa no período — ou de outra conta — devolve nil. Só banco, nunca a Meta.
class Crm::MetaAds::Panel::AdDetail
  QUOTES_LIMIT = 20

  def initialize(connection, ad_id:, days:)
    @connection = connection
    @ad_id = ad_id.to_s
    @report = Crm::MetaAds::Panel::Report.new(connection, days: days)
  end

  def payload
    return if row.nil?

    row.merge(
      days: @report.days, from: @report.first_day, to: @report.today, currency: @report.currency,
      preview_url: object&.preview_url, campaign_name: parent_name(:campaign_id), adset_name: parent_name(:adset_id),
      account_average_cost_per_sale: @report.average_cost_per_sale,
      reason: Crm::MetaAds::Panel::Verdict.reason(row, average_cost_per_sale: @report.average_cost_per_sale),
      daily: daily, quotes_list: quotes_list
    )
  end

  private

  def row
    return @row if defined?(@row)

    @row = @ad_id.present? ? @report.ads.find { |ad| ad[:ad_id] == @ad_id } : nil
  end

  def object
    return @object if defined?(@object)

    @object = Crm::MetaAdObject.find_by(account_id: @connection.account_id, meta_object_id: @ad_id)
  end

  # Nome da campanha e do conjunto pelo cache de nomes. O id vem do anúncio no cache; se ele ainda não foi
  # resolvido, do gasto do período, que a Meta manda com campanha e conjunto.
  def parent_name(column)
    id = object&.public_send(column).presence || @report.insights.where(ad_id: @ad_id).where.not(column => nil).pick(column)
    Crm::MetaAdObject.where(account_id: @connection.account_id, meta_object_id: id).pick(:name) if id
  end

  # Todos os dias do período, zeros incluídos: um dia sem gasto é informação ("o anúncio parou"), não buraco.
  # A conversa cai no dia do toque que a deu ao anúncio, no fuso da conta de anúncios (o mesmo do gasto).
  def daily
    spend = @report.insights.where(ad_id: @ad_id).group(:date).sum(:spend)
    conversations = @report.cohort.touches.values.select { |ad, _at| ad == @ad_id }
                           .map { |_ad, at| at.in_time_zone(@report.zone).to_date }.tally
    (@report.first_day..@report.today).map do |date|
      { date: date, spend: spend.fetch(date, 0).to_f.round(2), conversations: conversations.fetch(date, 0) }
    end
  end

  # Abertas primeiro, a que espera há mais tempo no topo — é quem pede retomada; depois as vendas.
  def quotes_list
    cards = @report.cohort.cards.select { |card| card.ad_id == @ad_id && card.quote? }
    cards.sort_by { |card| [card.sale? ? 1 : 0, card.waiting_since || Time.current] }.first(QUOTES_LIMIT).map do |card|
      { card_id: card.id, title: card.title, value: card.value, status: card.status, stage_name: card.stage_name,
        conversation_id: card.conversation_id, waiting_since: card.waiting_since }
    end
  end
end

# Os números do resumo diário (#1100, F4b): o dia de ontem no fuso da conta de anúncios, o mesmo em que a Meta
# conta o gasto.
#
# Gasto de `crm_meta_ad_insights_daily` (date = ontem); conversas, propostas e vendas da mesma coorte do painel
# (`Panel::Cohort`) com o intervalo de ontem; o anúncio que mais trouxe conversa; e o que fazer hoje, no período em
# que o painel abre (30 dias), para o resumo dizer o mesmo que a pessoa vê ao abrir.
#
# O que fazer hoje: com `with_ai: true` (o envio das 8h), o texto da IA (`Panel::AiAction`, decisão do Rodrigo em
# 07/10/2026). Ele sai do mesmo guardado do dia que o painel usa: se alguém já abriu o painel no idioma da conta,
# não há chamada nova; senão é uma chamada por conta por dia, só para quem ligou o resumo. IA desligada, sem
# credencial ou com falha: fica a regra (`Panel::Action`), como no painel. O envio de teste não chama a IA.
class Crm::MetaAds::WhatsappReport::Digest
  ACTION_DAYS = Crm::MetaAds::Panel::Report::PERIODS.last

  def initialize(connection, with_ai: false)
    @connection = connection
    @with_ai = with_ai
    @zone = (connection.ad_account_timezone.present? && ActiveSupport::TimeZone[connection.ad_account_timezone]) || Time.zone
  end

  def date
    @date ||= Time.current.in_time_zone(@zone).to_date - 1
  end

  def payload
    @payload ||= {
      date: date, currency: currency, spend: spend, conversations: cohort.conversation_ads.size,
      cost_per_conversation: ratio(spend, cohort.conversation_ads.size), quotes: cohort.cards.count(&:quote?),
      sales: sales.size, sales_value: sales.sum(&:value).round(2), best_ad: best_ad, action: action,
      ai_action: ai_action
    }
  end

  # Ontem sem gasto e sem conversa: não há o que contar. Não monta o `payload`, para não chamar a IA à toa.
  def nothing_to_report?
    spend.zero? && cohort.conversation_ads.empty?
  end

  private

  def insights
    Crm::MetaAdInsightDaily.where(account_id: @connection.account_id, ad_account_id: @connection.ad_account_id, date: date)
  end

  def spend
    @spend ||= insights.sum(:spend).to_f.round(2)
  end

  def currency
    insights.where.not(currency: nil).pick(:currency) || 'BRL'
  end

  def cohort
    @cohort ||= Crm::MetaAds::Panel::Cohort.new(@connection.account_id, date.in_time_zone(@zone).all_day)
  end

  def sales
    @sales ||= cohort.cards.select(&:sale?)
  end

  def best_ad
    ad_id, count = cohort.conversation_ads.values.compact.tally.max_by { |_id, total| total }
    return if ad_id.nil?

    name = Crm::MetaAdObject.where(account_id: @connection.account_id, meta_object_id: ad_id).pick(:name)
    { ad_id: ad_id, name: name.presence || ad_id, conversations: count }
  end

  def action
    Crm::MetaAds::Panel::Report.new(@connection, days: ACTION_DAYS).payload[:action]
  end

  # Só o texto que a IA de fato escreveu; a regra já está em `action`.
  def ai_action
    return unless @with_ai

    answer = Crm::MetaAds::Panel::AiAction.daily(connection: @connection, days: ACTION_DAYS,
                                                 language: Crm::MetaAds::WhatsappReport::MessageBuilder.new(@connection.account).language)
    answer if answer[:source] == 'ai'
  end

  def ratio(numerator, denominator)
    return if denominator.to_f.zero?

    (numerator.to_f / denominator).round(2)
  end
end

# Orçamento e datas do anúncio (#2198, pontos 5, 10 e 11). O dinheiro fica no grupo do anúncio, ou na campanha quando
# ela divide o dinheiro entre os grupos; as datas ficam sempre no grupo. A Meta guarda em centavos; aqui sai em reais.
#
# - `read` nunca devolve vazio: falha vira erro (`meta_unavailable`), e a tela diz "Não deu para ler o orçamento agora".
# - `active_ads_count`: quantos anúncios de onde está o dinheiro estão no ar. É com eles que um anúncio ativado divide.
# - `change!` revalida o valor (R$ 6 a R$ 500 por dia; o total só precisa ser positivo e ter fim) e as datas (o fim
#   depois de agora e do início), lê o orçamento de antes (para a Auditoria) e manda só o que mudou. O fim chega como a
#   tela mostrou ("2026-11-30T23:59:00") e vale no fuso da conta de anúncios.
# - Só o token do próprio cliente com ads_management muda; conta em outra moeda lê, mas não muda (os limites são em reais).
class Crm::MetaAds::Creation::Budget
  CENTS = 100

  def initialize(connection)
    @connection = connection
    @access = Crm::MetaAds::Creation::Access.new(connection)
  end

  def read(ad_id)
    data = read_ad(ad_id)
    adset = data['adset'].to_h
    campaign = data['campaign'].to_h
    holder = budget?(adset) ? adset : campaign
    raise Crm::MetaAds::Creation::Error, 'budget_not_found' unless budget?(holder)

    payload(holder, adset, holder.equal?(adset) ? 'adset' : 'campaign')
  end

  def change!(ad_id, amount:, end_time:)
    before = read(ad_id)
    raise Crm::MetaAds::Creation::Error, 'cannot_change' unless before[:can_change]

    value = parse_amount(amount, before[:kind])
    new_end = parse_end(end_time, before)
    apply!(before, value, new_end)
    { before: before, after: before.merge(amount: value, end_time: new_end&.iso8601) }
  end

  private

  def client
    @access.client
  end

  def read_ad(ad_id)
    raise Crm::MetaAds::Creation::Error, 'ad_not_found' unless Crm::MetaAds::Creation::Ids.numeric?(ad_id)

    result = client.ad_budget(ad_id)
    raise Crm::MetaAds::Creation::Error, 'meta_unavailable' if result.transient?
    raise Crm::MetaAds::Creation::Error, 'ad_not_found' unless result.ok && result.data['account_id'].to_s == @connection.ad_account_id.to_s

    result.data
  end

  def budget?(object)
    object['daily_budget'].to_i.positive? || object['lifetime_budget'].to_i.positive?
  end

  def payload(holder, adset, level)
    daily = holder['daily_budget'].to_i.positive?
    ads = count_ads(holder['id'])
    currency = read_currency
    {
      level: level, object_id: holder['id'].to_s, object_name: holder['name'], kind: daily ? 'daily' : 'lifetime',
      amount: (daily ? holder['daily_budget'] : holder['lifetime_budget']).to_i / CENTS.to_f, currency: currency,
      start_time: adset['start_time'], end_time: adset['end_time'].presence, started: started?(adset['start_time']),
      ads_count: ads.size, active_ads_count: ads.count('ACTIVE'),
      min_daily: Crm::MetaAds::Creation::Options::MIN_DAILY, max_daily: Crm::MetaAds::Creation::Options::MAX_DAILY,
      can_change: currency == Crm::MetaAds::Creation::Options::CURRENCY && @access.can_change_ads?,
      adset_id: adset['id'].to_s
    }
  end

  def count_ads(object_id)
    result = client.ads_of(object_id)
    raise Crm::MetaAds::Creation::Error.from_result(result) unless result.ok

    Array(result.data['data']).map { |ad| ad.to_h['effective_status'] }
  end

  def read_currency
    result = client.ad_account(@connection.ad_account_id)
    raise Crm::MetaAds::Creation::Error.from_result(result) unless result.ok

    result.data['currency'].to_s
  end

  def started?(start_time)
    start_time.present? && Time.zone.parse(start_time.to_s) <= Time.current
  end

  def parse_amount(amount, kind)
    value = BigDecimal(amount.to_s, exception: false)
    raise Crm::MetaAds::Creation::Error, 'invalid_amount' if value.nil? || !value.positive?
    return value.to_f if kind == 'lifetime'

    limits = Crm::MetaAds::Creation::Options::MIN_DAILY..Crm::MetaAds::Creation::Options::MAX_DAILY
    raise Crm::MetaAds::Creation::Error, 'invalid_amount' unless limits.cover?(value)

    value.to_f
  end

  # Sem fim: só no orçamento por dia (o total precisa de data para acabar).
  def parse_end(end_time, before)
    return no_end(before) if end_time.blank?

    parsed = zone.parse(end_time.to_s)
    raise Crm::MetaAds::Creation::Error, 'invalid_dates' unless parsed && parsed > [Time.current, time(before[:start_time])].compact.max

    parsed
  rescue ArgumentError
    raise Crm::MetaAds::Creation::Error, 'invalid_dates'
  end

  def no_end(before)
    raise Crm::MetaAds::Creation::Error, 'invalid_dates' if before[:kind] == 'lifetime'
  end

  def time(value)
    value.present? ? Time.zone.parse(value.to_s) : nil
  end

  def zone
    ActiveSupport::TimeZone[@connection.ad_account_timezone.to_s] || Time.zone
  end

  # O valor vai para onde está o dinheiro; o fim vai para o grupo. Tirar o fim manda 0 (confirmar na chamada real).
  def apply!(before, value, new_end)
    changes = Hash.new { |hash, key| hash[key] = {} }
    changes[before[:object_id]]["#{before[:kind]}_budget"] = (value * CENTS).round if value != before[:amount]
    changes[before[:adset_id]]['end_time'] = new_end ? new_end.iso8601 : 0 if end_changed?(time(before[:end_time]), new_end)
    changes.each do |object_id, params|
      result = client.update_object(object_id, params)
      raise Crm::MetaAds::Creation::Error.from_result(result) unless result.ok
    end
  end

  def end_changed?(old_end, new_end)
    old_end&.to_i != new_end&.to_i
  end
end

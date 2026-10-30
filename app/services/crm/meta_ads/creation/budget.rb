# Orçamento e datas do anúncio (#2198, pontos 5, 10 e 11). O dinheiro fica no grupo do anúncio, ou na campanha quando
# ela divide o dinheiro entre os grupos; as datas ficam sempre no grupo. A Meta guarda em centavos; aqui sai em reais.
#
# - `read` nunca devolve vazio: falha vira erro (`meta_unavailable`), e a tela diz "Não deu para ler o orçamento agora".
# - `active_ads_count`: quantos anúncios de onde está o dinheiro estão no ar. É com eles que um anúncio ativado divide.
# - `change!` revalida o valor (R$ 6 a R$ 500 por dia; o total, de R$ 6 até R$ 500 por dia de veiculação que falta) e
#   as datas (o fim depois de agora e do início), lê o orçamento de antes (para a Auditoria) e manda só o que mudou. O
#   fim chega como a tela mostrou ("2026-11-30T23:59:00") e vale no fuso da conta de anúncios. Tirar a data de fim que
#   já existe fica recusado até a chamada real confirmar como a Meta aceita (item 11 do contrato).
# - Quando o valor fica na campanha e o fim no grupo, são duas chamadas. Se a segunda falha, a primeira é desfeita; se
#   nem isso der, o erro é `meta_partial`, com o que mudou, para a Auditoria registrar a verdade.
# - Só o token do próprio cliente com ads_management muda; conta em outra moeda lê, mas não muda (os limites são em reais).
# - Dinheiro sem float (Crm::MetaAds::Creation::Money): mais de 2 casas é recusa. `today`: o dia de hoje no fuso da conta
#   de anúncios, para a tela não usar o relógio do navegador.
class Crm::MetaAds::Creation::Budget
  MONEY = Crm::MetaAds::Creation::Money

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

    new_end = parse_end(end_time, before)
    value = parse_amount(amount, before, new_end)
    apply!(before, value, new_end)
    { before: before, after: before.merge(amount: MONEY.text(value), end_time: new_end&.iso8601) }
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
    currency = MONEY.currency!(client, @connection.ad_account_id)
    {
      level: level, object_id: holder['id'].to_s, object_name: holder['name'], kind: daily ? 'daily' : 'lifetime',
      amount: amount_of(holder, daily), currency: currency,
      start_time: adset['start_time'], end_time: adset['end_time'].presence, started: started?(adset['start_time']),
      ads_count: ads.size, active_ads_count: ads.count('ACTIVE'),
      min_daily: Crm::MetaAds::Creation::Options::MIN_DAILY, max_daily: Crm::MetaAds::Creation::Options::MAX_DAILY,
      can_change: currency == MONEY::CURRENCY && @access.can_change_ads?,
      adset_id: adset['id'].to_s, today: zone.today.iso8601
    }
  end

  # Em reais, texto decimal para a tela ("30.00"); a conta e a comparação usam os centavos (MONEY.cents).
  def amount_of(holder, daily)
    MONEY.text(MONEY.from_cents(daily ? holder['daily_budget'] : holder['lifetime_budget']))
  end

  def count_ads(object_id)
    result = client.ads_of(object_id)
    raise Crm::MetaAds::Creation::Error.from_result(result) unless result.ok

    Array(result.data['data']).map { |ad| ad.to_h['effective_status'] }
  end

  def started?(start_time)
    start_time.present? && Time.zone.parse(start_time.to_s) <= Time.current
  end

  def parse_amount(amount, before, new_end)
    value = MONEY.parse(amount)
    raise Crm::MetaAds::Creation::Error, 'invalid_amount' unless value && limits(before, new_end).cover?(value)

    value
  end

  # Por dia: R$ 6 a R$ 500. Total: R$ 6 até R$ 500 vezes os dias de veiculação que faltam.
  def limits(before, new_end)
    min = Crm::MetaAds::Creation::Options::MIN_DAILY
    max = Crm::MetaAds::Creation::Options::MAX_DAILY
    return min..max if before[:kind] == 'daily'

    from = [Time.current, time(before[:start_time])].compact.max
    days = [((new_end - from) / 1.day).ceil, 1].max
    min..(max * days)
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
    raise Crm::MetaAds::Creation::Error, 'cannot_clear_end' if before[:end_time].present?
  end

  def time(value)
    value.present? ? Time.zone.parse(value.to_s) : nil
  end

  def zone
    @zone ||= Crm::MetaAds::Creation::AccountZone.new(@connection, client).zone
  end

  # O valor vai para onde está o dinheiro; o fim vai para o grupo (no mesmo objeto, uma chamada só).
  def apply!(before, value, new_end)
    changes = Hash.new { |hash, key| hash[key] = { new: {}, old: {} } }
    add_change(changes[before[:object_id]], "#{before[:kind]}_budget", cents(value), cents(before[:amount])) if cents(value) != cents(before[:amount])
    add_change(changes[before[:adset_id]], 'end_time', new_end.iso8601, before[:end_time]) if end_changed?(time(before[:end_time]), new_end)
    send_all!(changes)
  end

  def add_change(target, key, new_value, old_value)
    target[:new][key] = new_value
    target[:old][key] = old_value if old_value.present?
  end

  def send_all!(changes)
    done = []
    changes.each do |object_id, params|
      result = client.update_object(object_id, params[:new])
      raise undo_partial(done, result) unless result.ok

      done << [object_id, params]
    end
  end

  # Desfaz o que já mudou. Sem conseguir, `meta_partial` com o que ficou mudado na Meta.
  def undo_partial(done, failure)
    left = done.reject { |object_id, params| params[:old].present? && client.update_object(object_id, params[:old]).ok }
    return Crm::MetaAds::Creation::Error.from_result(failure) if left.empty?

    Crm::MetaAds::Creation::Error.new('meta_partial', nothing_created: false, details: left.to_h.transform_values { |params| params[:new] })
  end

  def cents(value)
    MONEY.cents(value)
  end

  def end_changed?(old_end, new_end)
    old_end&.to_i != new_end&.to_i
  end
end

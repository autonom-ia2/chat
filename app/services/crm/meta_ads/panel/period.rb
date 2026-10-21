# O período do painel de Anúncios (#2011): os últimos 7, 30 ou 90 dias contando hoje, este mês, o mês passado ou
# desde o primeiro anúncio. Os dias são do fuso da conta (o mesmo do Report). Sai de um nome (`period`), e o `days`
# antigo (7 ou 30) continua valendo para quem já pede assim. Nome desconhecido cai nos 30 dias.
#
# "Desde o primeiro anúncio" começa no dia do primeiro toque de anúncio da conta (`first_ad_day`, lido só quando
# este período é o pedido) e nunca antes de MAX_MONTHS: é até onde a Meta devolve o gasto.
class Crm::MetaAds::Panel::Period
  ROLLING = { '7d' => 7, '30d' => 30, '90d' => 90 }.freeze
  KEYS = (ROLLING.keys + %w[this_month last_month all]).freeze
  DEFAULT = '30d'.freeze
  MAX_MONTHS = 37

  attr_reader :key, :first_day, :last_day

  def self.key_for(period: nil, days: nil)
    return period.to_s if KEYS.include?(period.to_s)

    rolling = "#{days.to_i}d"
    ROLLING.key?(rolling) ? rolling : DEFAULT
  end

  # first_ad_day: bloco que devolve o dia do primeiro anúncio (Date ou nil); só é chamado para 'all'.
  def initialize(key, today:, first_ad_day: nil)
    @key = KEYS.include?(key) ? key : DEFAULT
    @today = today
    @first_day, @last_day = bounds(first_ad_day)
  end

  def days
    (last_day - first_day).to_i + 1
  end

  # Últimos `days` dias contando hoje? O consultor só reaproveita a coorte da tela nos 30 dias móveis.
  def rolling?(days)
    ROLLING[key] == days
  end

  # O período termina hoje (os números ainda mudam) ou já fechou (mês passado)?
  def open?
    last_day == @today
  end

  private

  def bounds(first_ad_day)
    return [@today - (ROLLING[key] - 1), @today] if ROLLING.key?(key)
    return [@today.beginning_of_month, @today] if key == 'this_month'
    return [@today.prev_month.beginning_of_month, @today.prev_month.end_of_month] if key == 'last_month'

    [since_first_ad(first_ad_day&.call), @today]
  end

  def since_first_ad(day)
    limit = @today << MAX_MONTHS
    day.nil? ? @today : [day, limit].max
  end
end

# Período do painel de resultados do agendamento (#1194, J7-A1): os últimos 7 ou 30 dias, contando hoje, no fuso
# da conta (o mesmo dos relatórios, `reporting_timezone`; sem ele, o do servidor). Vai do começo do primeiro dia
# até agora. Qualquer outro valor é recusado com InviteError 'invalid_period'.
class Crm::BookingV2::ResultsPeriod
  DAYS = [7, 30].freeze
  DEFAULT_DAYS = 30

  attr_reader :days

  def initialize(account:, days: nil)
    @account = account
    @days = days.blank? ? DEFAULT_DAYS : DAYS.find { |allowed| allowed.to_s == days.to_s }
    raise Crm::BookingV2::InviteError, 'invalid_period' if @days.nil?
  end

  def range
    since..until_time
  end

  def since
    @since ||= time_zone.now.beginning_of_day - (days - 1).days
  end

  def until_time
    @until_time ||= Time.current
  end

  def as_json(*)
    { days: days, since: since.iso8601, until: until_time.in_time_zone(time_zone).iso8601, timezone: time_zone.tzinfo.name }
  end

  private

  attr_reader :account

  def time_zone
    @time_zone ||= ActiveSupport::TimeZone[account.reporting_timezone.to_s] || Time.zone
  end
end

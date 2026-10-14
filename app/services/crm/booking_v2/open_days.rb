# Dias que uma página nova oferece, para a tela montar os cartões de dia sem repetir a regra do `Slots`: a página
# pública (#1195, J2-A8) e a janela "Agendar reunião" do painel (#1285) leem daqui.
#
# `booking_window_days`: a janela, de hoje em diante. `weekdays`: dias da semana em que a página atende (0 = domingo
# ... 6 = sábado). `closed_dates`: feriados nacionais (`Crm::Calendar::Holidays`) da janela, como YYYY-MM-DD no fuso
# da página; só com `close_holidays` ligado, que é quando o `Slots` não oferece horário neles.
#
# São os dias da PÁGINA. Quem atende pode ter horários próprios ou a agenda cheia (`Slots` cruza os dois), então um
# dia daqui pode não ter horário: a tela mostra "nenhum horário" e aponta o próximo livre.
#
# `time_zone`: o fuso da página, sempre válido (`resolved_timezone` cai no padrão quando o gravado não serve).
class Crm::BookingV2::OpenDays
  def initialize(profile, time_zone)
    @profile = profile
    @time_zone = time_zone
  end

  def to_h
    { booking_window_days: profile.booking_window_days, weekdays: profile.weekdays.sort, closed_dates: closed_dates }
  end

  private

  attr_reader :profile, :time_zone

  def closed_dates
    return [] unless profile.close_holidays?

    today = Time.current.in_time_zone(time_zone).to_date
    (today..(today + profile.booking_window_days)).select { |day| Crm::Calendar::Holidays.holiday?(day) }.map(&:iso8601)
  end
end

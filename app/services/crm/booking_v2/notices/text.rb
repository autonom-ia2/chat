# Texto dos avisos ao cliente (#1192): curto, leigo e genérico (serve qualquer negócio), no idioma da conta, com o
# link de gestão (`/b/<code>`) e SEMPRE a linha para parar os avisos (J2-A9, RA-18). O link de parar é o mesmo link
# de gestão com `?stop_notices=1`: a página abre já oferecendo "Parar avisos".
#
# `when_text` também alimenta o modelo aprovado ({{2}}) e as notificações ao agente.
class Crm::BookingV2::Notices::Text
  STOP_PARAM = '?stop_notices=1'.freeze

  def self.when_text(meeting)
    zone = ActiveSupport::TimeZone[meeting.timezone.to_s] || Time.zone
    format = I18n.t('crm.booking_v2.notices.when_format', locale: locale(meeting.account))
    meeting.starts_at.in_time_zone(zone).strftime(format)
  end

  def self.locale(account)
    Crm::BookingV2::LocationLabel.locale(account)
  end

  def self.stop_url(invite)
    "#{invite.url}#{STOP_PARAM}"
  end

  def initialize(meeting:, invite:, kind:)
    @meeting = meeting
    @invite = invite
    @kind = kind.to_s
  end

  def to_s
    body = I18n.t("crm.booking_v2.notices.#{kind}", name: name_part, when: self.class.when_text(meeting), link: invite.url, locale: locale)
    "#{body}\n\n#{stop_line}"
  end

  # Depois do corpo de um modelo do canal API (que só tem variáveis de contato): dia e hora, link de gestão e a
  # linha de parar.
  def appendix
    "#{self.class.when_text(meeting)} - #{invite.url}\n\n#{stop_line}"
  end

  # Valores do modelo aprovado, na ordem das variáveis: {{1}} primeiro nome, {{2}} dia e hora, {{3}} link de gestão.
  def template_values
    [Crm::BookingV2::InviteText.first_name(invite.contact), self.class.when_text(meeting), invite.url]
  end

  private

  attr_reader :meeting, :invite, :kind

  def stop_line
    I18n.t('crm.booking_v2.notices.stop_line', link: self.class.stop_url(invite), locale: locale)
  end

  def name_part
    first = Crm::BookingV2::InviteText.first_name(invite.contact)
    first.empty? ? '' : ", #{first}"
  end

  def locale
    self.class.locale(meeting.account)
  end
end

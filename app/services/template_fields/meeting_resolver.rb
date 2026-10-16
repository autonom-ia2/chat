# horario.* (#1331): a reunião do agendamento e o convite dela.
#
# Dia e hora é exatamente o texto dos avisos (`Crm::BookingV2::Notices::Text.when_text`: "14/10 às 15:00" no fuso da
# reunião e no idioma da conta). Data e hora sozinhas usam o mesmo fuso. A ordem dos avisos aprovados fica em
# NOTICE_KEYS: {{1}} primeiro nome, {{2}} dia e hora, {{3}} link de gestão.
class TemplateFields::MeetingResolver
  include TemplateFields::FieldReader

  # `horario.link_codigo` (#1518/#1524): só o código do link de gestão (o fim de `/b/<código>`), para o botão de URL
  # dinâmica do modelo (`https://<base>/b/{{1}}`). Lido do próprio link de gestão, sem outra regra de montar o link.
  READERS = {
    'horario.data_hora' => :when_text, 'horario.data' => :date, 'horario.hora' => :time, 'horario.link_gestao' => :manage_url,
    'horario.link_codigo' => :manage_code
  }.freeze
  NOTICE_KEYS = %w[cliente.primeiro_nome horario.data_hora horario.link_gestao].freeze

  def initialize(meeting, invite: nil)
    @meeting = meeting
    @invite = invite
  end

  private

  attr_reader :meeting, :invite

  def when_text
    Crm::BookingV2::Notices::Text.when_text(meeting)
  end

  def date
    TemplateFields::Format.date(meeting.starts_at, zone)
  end

  def time
    TemplateFields::Format.time(meeting.starts_at, zone)
  end

  def manage_url
    invite&.url
  end

  def manage_code
    url = manage_url
    url && URI.parse(url).path.to_s.split('/').last
  end

  # O mesmo fuso de `Notices::Text.when_text`.
  def zone
    ActiveSupport::TimeZone[meeting.timezone.to_s] || Time.zone
  end
end

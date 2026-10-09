# Arquivo de calendário (RFC 5545) de uma reunião, para "Salvar na minha agenda" (#1188, J2-A11).
#
# Evento importável: sem METHOD, sem ORGANIZER e sem ATTENDEE (nenhum e-mail sai no arquivo). UID estável por
# reunião, SEQUENCE para remarcação, horários em UTC. Escape e dobra de linha com métodos de String (sem regex):
# linhas de até 75 octetos, continuação com CRLF + espaço, sem partir caractere UTF-8 no meio.
class Crm::Meetings::IcsBuilder
  CRLF = "\r\n".freeze
  MAX_LINE_OCTETS = 75
  PRODID = '-//Chat2You//Agendamento//PT-BR'.freeze
  TIME_FORMAT = '%Y%m%dT%H%M%SZ'.freeze

  def initialize(meeting:, uid_host: nil, location_label: nil, sequence: nil)
    @meeting = meeting
    @uid_host = uid_host.presence || default_uid_host
    @location_label = location_label
    @sequence = sequence
  end

  def build
    lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', "PRODID:#{PRODID}", 'CALSCALE:GREGORIAN', 'BEGIN:VEVENT']
    lines.concat(event_lines)
    lines.push('END:VEVENT', 'END:VCALENDAR')
    lines.map { |line| fold(line) }.join(CRLF) + CRLF
  end

  ESCAPES = [['\\', '\\\\'], [';', '\\;'], [',', '\\,'], ["\r\n", '\\n'], ["\r", '\\n'], ["\n", '\\n']].freeze

  # Bloco no gsub: o texto de troca entra literal (sem interpretar barra invertida).
  def self.escape(value)
    ESCAPES.reduce(value.to_s) { |text, (from, to)| text.gsub(from) { to } }
  end

  private

  attr_reader :meeting

  def event_lines
    [
      "UID:meeting-#{meeting.id}@#{@uid_host}",
      "SEQUENCE:#{sequence}",
      "DTSTAMP:#{format_time(Time.current)}",
      "DTSTART:#{format_time(meeting.starts_at)}",
      "DTEND:#{format_time(meeting.ends_at)}",
      "SUMMARY:#{self.class.escape(meeting.title)}"
    ] + detail_lines
  end

  def detail_lines
    lines = []
    lines <<"DESCRIPTION:#{self.class.escape(meeting.description)}" if meeting.description.present?
    lines << "LOCATION:#{self.class.escape(location_text)}" if location_text.present?
    lines << "URL:#{meeting.online_meeting_url}" if web_url?(meeting.online_meeting_url)
    lines << "STATUS:#{meeting.canceled? ? 'CANCELLED' : 'CONFIRMED'}"
    lines
  end

  def sequence
    (@sequence || meeting.metadata.to_h['ics_sequence']).to_i
  end

  def location_text
    location = meeting.metadata.to_h['location'].to_h
    location['address'].presence || @location_label.presence || location['label'].presence
  end

  def format_time(time)
    time.utc.strftime(TIME_FORMAT)
  end

  def web_url?(value)
    return false if value.blank?

    uri = URI.parse(value.to_s)
    uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end

  # Primeira linha com até 75 octetos; as seguintes começam com espaço, que conta nos 75.
  def fold(line)
    return line if line.bytesize <= MAX_LINE_OCTETS

    parts = [+'']
    line.each_char do |char|
      limit = parts.size == 1 ? MAX_LINE_OCTETS : MAX_LINE_OCTETS - 1
      parts << +'' if parts.last.bytesize + char.bytesize > limit
      parts.last << char
    end
    parts.join("#{CRLF} ")
  end

  def default_uid_host
    URI.parse(ENV.fetch('FRONTEND_URL', '')).host.presence || 'chat2you.local'
  rescue URI::InvalidURIError
    'chat2you.local'
  end
end

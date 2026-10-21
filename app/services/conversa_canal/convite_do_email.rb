require 'icalendar'
require 'icalendar/tzinfo'

# Convite de reunião dentro do e-mail recebido (#1984). O Teams, o Meet e o Outlook mandam o convite como uma parte
# `text/calendar` (RFC 5545) ao lado do texto e do HTML; o Chatwoot guarda só o texto e o HTML. Aqui a parte do
# calendário vira o `convite` de content_attributes.email: o que o cartão da conversa mostra e o que a resposta
# (ConversaCanal::RespostaDoConvite) precisa para achar o evento.
# - Só convite (REQUEST) e cancelamento (CANCEL); resposta de outra pessoa (REPLY) e o resto ficam de fora.
# - Horário com o fuso do próprio convite (o Outlook usa nomes do Windows, resolvidos pelo VTIMEZONE que vem junto).
# - Convite ilegível não quebra o recebimento do e-mail: fica sem cartão, com o motivo no log.
class ConversaCanal::ConviteDoEmail
  METODOS = %w[REQUEST CANCEL].freeze
  TIPOS = %w[text/calendar application/ics].freeze
  LIMITE = 256.kilobytes
  # O link da chamada: primeiro o campo próprio de cada aplicativo, depois o local e a descrição. Só de aplicativo
  # conhecido: o botão "Entrar" não leva a endereço qualquer que veio no convite.
  CAMPOS_DO_LINK = %w[x_microsoft_skypeteamsmeetingurl x_google_conference].freeze
  APLICATIVOS = %w[teams.microsoft.com teams.live.com meet.google.com zoom.us].freeze

  def self.ler(mail)
    new(mail).ler
  end

  def initialize(mail)
    @mail = mail
  end

  def ler
    texto = texto_do_calendario
    return if texto.blank?

    @calendario = Icalendar::Calendar.parse(texto).first
    evento = evento_do_convite
    montar(evento) if evento
  rescue StandardError => e
    Rails.logger.warn("[ConviteDoEmail] convite ilegível no e-mail #{@mail.message_id}: #{e.class} #{e.backtrace&.first}")
    nil
  end

  private

  def metodo
    @calendario&.ip_method.to_s.upcase
  end

  # O evento de convite (REQUEST) ou de cancelamento (CANCEL), com dia e hora.
  def evento_do_convite
    evento = @calendario&.events&.first
    evento if evento&.dtstart && METODOS.include?(metodo)
  end

  def texto_do_calendario
    parte = partes(@mail).find { |p| TIPOS.include?(p.mime_type.to_s.downcase) }
    return if parte.nil? || parte.body.raw_source.to_s.bytesize > LIMITE * 2

    corpo = parte.decoded.to_s
    return if corpo.bytesize > LIMITE

    corpo.dup.force_encoding(Encoding::UTF_8).scrub
  end

  # As partes do próprio e-mail. Um e-mail encaminhado como anexo (message/rfc822) fica de fora: o convite dele é
  # de outra pessoa e não se responde daqui.
  def partes(parte)
    return [parte] unless parte.multipart?

    parte.parts.reject { |filha| filha.mime_type.to_s.downcase == 'message/rfc822' }.flat_map { |filha| partes(filha) }
  end

  def montar(evento)
    {
      uid: evento.uid.to_s,
      sequencia: evento.sequence.to_i,
      metodo: metodo,
      titulo: evento.summary.to_s.strip,
      local: evento.location.to_s.strip.presence,
      link: link_da_chamada(evento),
      organizador: pessoa(evento.organizer),
      convidados: convidados(evento)
    }.merge(datas(evento)).compact
  end

  def datas(evento)
    {
      dia_inteiro: dia_inteiro?(evento.dtstart),
      fuso_incerto: (true unless fuso_conhecido?(evento.dtstart)),
      inicio: segundos(evento.dtstart),
      fim: fim(evento),
      recorrente: (true if evento.rrule.present?),
      ocorrencia: segundos(evento.recurrence_id)
    }
  end

  def convidados(evento)
    Array(evento.attendee).filter_map do |convidado|
      dados = pessoa(convidado)
      dados.merge(resposta: convidado.ical_params['partstat']&.first) if dados[:email]
    end
  end

  # Sem DTEND, o fim sai de DTSTART + DURATION (RFC 5545 §3.6.1).
  def fim(evento)
    return segundos(evento.dtend) if evento.dtend
    # Dia inteiro sem fim nem duração dura o próprio dia (RFC 5545 §3.6.1).
    return segundos(evento.dtstart) + 1.day.to_i if evento.duration.nil? && dia_inteiro?(evento.dtstart)
    return if evento.duration.nil?

    segundos(evento.dtstart) + segundos_da_duracao(evento.duration.value)
  end

  def segundos_da_duracao(duracao)
    ((((duracao.weeks.to_i * 7) + duracao.days.to_i) * 24) + duracao.hours.to_i).hours.to_i +
      (duracao.minutes.to_i * 60) + duracao.seconds.to_i
  end

  # Horário com fuso que dá para resolver: UTC, um nome do banco de fusos ou um VTIMEZONE que veio no convite. Horário
  # "flutuante" (sem fuso) ou com um nome que ninguém conhece é lido como UTC e pode estar errado: o cartão avisa.
  def fuso_conhecido?(valor)
    return true if dia_inteiro?(valor)

    tzid = valor.ical_params['tzid']&.first.to_s
    return false if tzid.blank?

    ActiveSupport::TimeZone[tzid].present? || @calendario.timezones.any? { |fuso| fuso.tzid.to_s == tzid }
  end

  def dia_inteiro?(valor)
    valor.is_a?(Icalendar::Values::Date)
  end

  # Dia inteiro: meio-dia UTC do dia, para nenhum fuso trocar a data.
  def segundos(valor)
    return if valor.nil?
    return Time.utc(valor.year, valor.month, valor.day, 12).to_i if dia_inteiro?(valor)

    valor.to_time.to_i
  end

  def pessoa(valor)
    return {} if valor.nil?

    email = endereco_unico(valor.to_s.delete_prefix('mailto:').delete_prefix('MAILTO:').strip.downcase)
    nome = valor.ical_params['cn']&.first.to_s.strip
    { nome: (nome if nome.present? && nome.downcase != email), email: email }.compact
  end

  # Um endereço só, escrito sozinho. Lista ("a@x.com,b@y.com"), grupo ("lista: a@x.com, b@y.com;") ou texto com nome
  # não passam: o ORGANIZER vira o destinatário da resposta, e uma lista faria da caixa um disparador de e-mail.
  def endereco_unico(texto)
    enderecos = Mail::AddressList.new(texto).addresses
    texto if enderecos.size == 1 && enderecos.first.address == texto
  rescue Mail::Field::ParseError
    nil
  end

  def link_da_chamada(evento)
    proprio = CAMPOS_DO_LINK.lazy.map { |campo| evento.custom_property(campo).first.to_s.strip }.find(&:present?)
    return proprio if link_de_chamada?(proprio)

    [evento.location, evento.description].lazy.flat_map { |t| t.to_s.split }.find { |p| link_de_chamada?(p) }
  end

  def link_de_chamada?(palavra)
    return false unless endereco_web?(palavra)

    host = URI.parse(palavra).host.to_s
    APLICATIVOS.any? { |d| host == d || host.end_with?(".#{d}") }
  rescue URI::InvalidURIError
    false
  end

  def endereco_web?(texto)
    texto.to_s.start_with?('https://')
  end
end

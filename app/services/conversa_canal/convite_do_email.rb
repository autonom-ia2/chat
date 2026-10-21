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
  PERIODOS = { 'SECONDLY' => 1.second, 'MINUTELY' => 1.minute, 'HOURLY' => 1.hour, 'DAILY' => 1.day, 'WEEKLY' => 1.week,
               'MONTHLY' => 1.month, 'YEARLY' => 1.year }.freeze
  # Partes da RRULE que podem deixar um período inteiro sem ocorrência (o dia 31 no mês de 30, a 5ª segunda): com elas, o
  # limite do COUNT por períodos não vale.
  PARTES_QUE_PULAM = %i[by_second by_minute by_hour by_month_day by_year_day by_week_number by_month by_set_position].freeze
  # Até onde um horário "flutuante" pode estar à frente de UTC (o fuso mais a oeste é UTC-12).
  FUSO_MAIS_A_OESTE = 12.hours

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
      # Quando o organizador gerou esta versão (DTSTAMP): desempata o CANCEL e o REQUEST de mesma SEQUENCE (#1995).
      carimbo: segundos(evento.dtstamp),
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
      fim_da_serie: fim_da_serie(evento),
      ocorrencia: segundos(evento.recurrence_id),
      ocorrencia_original: ocorrencia_original(evento.recurrence_id)
    }
  end

  # Fim da série que acaba (RRULE com UNTIL ou COUNT, #1995): depois dele o convite não se responde. É um limite por
  # cima, calculado sem percorrer as ocorrências (uma regra de minuto em minuto até 2099 não pode travar o recebimento):
  # o cartão pode perguntar um pouco além do fim real, nunca parar antes dele. Regra que o limite não cobre (mais de uma
  # RRULE, partes que pulam períodos) fica sem fim_da_serie e segue respondível, como série sem fim.
  def fim_da_serie(evento)
    regra = evento.rrule.first if evento.rrule.size == 1
    return if regra.nil?

    ultima = regra.until ? limite_do_until(regra.until.to_s) : limite_do_count(regra, evento.dtstart)
    return if ultima.nil?

    # O DTSTART sempre é uma ocorrência (RFC 5545), mesmo com um UNTIL anterior a ele.
    [ultima, segundos(evento.dtstart)].max + duracao(evento)
  rescue StandardError => e
    Rails.logger.warn("[ConviteDoEmail] fim da série ilegível no e-mail #{@mail.message_id}: #{e.class}")
    nil
  end

  def duracao(evento)
    (fim(evento).to_i - segundos(evento.dtstart)).clamp(0..)
  end

  # Nenhuma ocorrência começa depois do UNTIL (RFC 5545 §3.3.10). Só com data, vale o dia inteiro; sem fuso (sem o Z),
  # pode ser de qualquer fuso: os dois casos contam até onde o dia ou o horário termina no fuso mais a oeste.
  def limite_do_until(texto)
    utc = ActiveSupport::TimeZone['UTC']
    return (utc.strptime(texto, '%Y%m%d') + 1.day + FUSO_MAIS_A_OESTE).to_i - 1 unless texto.include?('T')
    return utc.strptime(texto, '%Y%m%dT%H%M%SZ').to_i if texto.end_with?('Z')

    (utc.strptime(texto, '%Y%m%dT%H%M%S') + FUSO_MAIS_A_OESTE).to_i
  end

  # COUNT: cada período (dia, semana, mês…) tem pelo menos uma ocorrência; o limite é o começo mais COUNT períodos (um
  # a mais que o necessário). Semanal com vários dias (BYDAY=MO,WE) junta as ocorrências por semana.
  def limite_do_count(regra, dtstart)
    periodo = PERIODOS[regra.frequency.to_s.upcase]
    return if periodo.nil? || regra.count.nil? || pula_periodo?(regra, dtstart)

    limite = (comeco_da_serie(dtstart) + (periodo * (periodos(regra) * [regra.interval.to_i, 1].max))).to_i
    # Horário flutuante foi lido como UTC: no fuso mais a oeste, a série acaba até 12 h depois (pesa na de hora em hora).
    fuso_conhecido?(dtstart) ? limite : limite + FUSO_MAIS_A_OESTE.to_i
  end

  def periodos(regra)
    dias = Array(regra.by_day).size
    dias > 1 ? (regra.count.to_f / dias).ceil + 1 : regra.count.to_i
  end

  # BYDAY fora do semanal (2ª terça do mês, só dias úteis num diário) e o dia 29 em diante num mês ou ano (o mês sem
  # esse dia fica sem ocorrência) também pulam períodos.
  def pula_periodo?(regra, dtstart)
    return true if PARTES_QUE_PULAM.any? { |parte| Array(regra.public_send(parte)).any? }
    return true if Array(regra.by_day).any? && regra.frequency.to_s.upcase != 'WEEKLY'

    %w[MONTHLY YEARLY].include?(regra.frequency.to_s.upcase) && comeco_da_serie(dtstart).day > 28
  end

  # O horário com a diferença do fuso do convite (o VTIMEZONE do Outlook incluído). Dia inteiro, ao meio-dia UTC, como
  # no resto do convite.
  def comeco_da_serie(valor)
    dia_inteiro?(valor) ? Time.zone.at(segundos(valor)).utc : valor.to_time
  end

  # RECURRENCE-ID sem fuso conhecido (horário flutuante ou nome que ninguém resolve, #1995): a resposta devolve o valor
  # como veio, e o organizador acha a ocorrência pelo mesmo texto. Com fuso conhecido, os segundos em UTC bastam.
  def ocorrencia_original(valor)
    return if valor.nil? || fuso_conhecido?(valor)

    { valor: valor.value_ical, tzid: valor.ical_params['tzid']&.first.presence }.compact
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

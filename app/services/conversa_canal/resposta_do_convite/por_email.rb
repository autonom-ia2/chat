require 'net/http'
require 'icalendar'

# Resposta ao convite por e-mail (#1984), para a caixa sem agenda ligada: o e-mail padrão de resposta de calendário
# (iMIP, RFC 6047) ao organizador, com a parte text/calendar METHOD:REPLY e a situação da caixa no ATTENDEE. O Google
# Agenda, o Outlook e o Apple Calendar do organizador leem essa parte e marcam a resposta no evento.
# Sai pela própria caixa, como as respostas da conversa: Microsoft pelo Graph (sendMail), Google pelo SMTP com OAuth, as
# demais pelo SMTP configurado na caixa. Caixa sem envio próprio (só encaminhamento) não responde.
class ConversaCanal::RespostaDoConvite::PorEmail
  PARTSTAT = { 'aceito' => 'ACCEPTED', 'talvez' => 'TENTATIVE', 'recusado' => 'DECLINED' }.freeze
  GRAPH_ENVIO = 'https://graph.microsoft.com/v1.0/me/sendMail'.freeze
  TEMPO = { open_timeout: 15, read_timeout: 30 }.freeze
  # O título vem de quem mandou o convite: no assunto, só o começo.
  TITULO = 120

  pattr_initialize [:channel!, :convite!, :resposta!, :endereco!]

  def perform
    raise ConversaCanal::RespostaDoConvite::Recusa, I18n.t('conversa_canal.convite.sem_envio') unless envia?

    channel.microsoft? ? pelo_graph(email) : pelo_smtp(email)
  rescue ConversaCanal::RespostaDoConvite::Recusa, ConversaCanal::RespostaDoConvite::FalhaNoEnvio
    raise
  rescue StandardError => e
    Rails.logger.warn("[RespostaDoConvite] e-mail de resposta não saiu (caixa #{channel.id}): #{e.class}")
    raise ConversaCanal::RespostaDoConvite::FalhaNoEnvio, e.class.name
  end

  private

  def envia?
    channel.microsoft? || channel.google? || channel.smtp_enabled
  end

  def email
    @email ||= Mail.new.tap do |mail|
      # From é o login da caixa (o servidor reescreveria outro); o ATTENDEE leva o endereço convidado.
      mail.from = channel.email
      mail.to = convite.dig('organizador', 'email')
      mail.subject = I18n.t("conversa_canal.convite.assunto.#{resposta}", titulo: convite['titulo'].to_s.truncate(TITULO))
      mail.message_id = "<convite-#{SecureRandom.hex(12)}@#{channel.email.split('@').last}>"
      montar_partes(mail)
    end
  end

  # multipart/alternative com o texto e o calendário, como o Google e o Outlook mandam: o Exchange só reconhece a
  # resposta de reunião nesse formato.
  def montar_partes(mail)
    mail.content_type = 'multipart/alternative'
    mail.add_part(Mail::Part.new(content_type: 'text/plain; charset=UTF-8', body: I18n.t("conversa_canal.convite.corpo.#{resposta}")))
    mail.add_part(Mail::Part.new(content_type: 'text/calendar; method=REPLY; charset=UTF-8', body: calendario.to_ical))
  end

  def calendario
    Icalendar::Calendar.new.tap do |cal|
      cal.prodid = '-//Chat2You//Convite da reuniao//PT'
      cal.ip_method = 'REPLY'
      cal.event do |evento|
        identificar(evento)
        datar(evento)
      end
    end
  end

  # O que o organizador usa para achar o evento e a pessoa: UID, SEQUENCE, ORGANIZER e o ATTENDEE com a resposta.
  def identificar(evento)
    evento.uid = convite['uid']
    evento.sequence = convite['sequencia'].to_i
    evento.organizer = Icalendar::Values::CalAddress.new("mailto:#{convite.dig('organizador', 'email')}")
    evento.append_attendee(Icalendar::Values::CalAddress.new("mailto:#{endereco}", 'partstat' => PARTSTAT.fetch(resposta)))
  end

  def datar(evento)
    evento.dtstamp = Icalendar::Values::DateTime.new(Time.now.utc, 'tzid' => 'UTC')
    evento.dtstart = horario(convite['inicio']) if convite['inicio']
    evento.dtend = horario(convite['fim']) if convite['fim']
    evento.recurrence_id = ocorrencia if convite['ocorrencia']
  end

  # A ocorrência que chegou sem fuso conhecido volta como veio (o mesmo texto e o mesmo TZID, #1995): convertida para
  # UTC, ela apontaria outro horário e o organizador não acharia a ocorrência. Com TZID, sai sem o VTIMEZONE que a
  # RFC 5545 pede: o convite não trouxe um que dê para copiar, e é o mesmo TZID que o organizador mandou.
  def ocorrencia
    original = convite['ocorrencia_original']
    return horario(convite['ocorrencia']) if original.blank?

    Icalendar::Values::DateTime.new(original['valor'], original['tzid'] ? { 'tzid' => original['tzid'] } : {})
  end

  def horario(segundos)
    momento = Time.at(segundos.to_i).utc
    return Icalendar::Values::Date.new(momento.to_date) if convite['dia_inteiro']

    Icalendar::Values::DateTime.new(momento, 'tzid' => 'UTC')
  end

  def pelo_graph(mail)
    pedido = Net::HTTP::Post.new(URI(GRAPH_ENVIO))
    pedido['Authorization'] = "Bearer #{Microsoft::GraphTokenService.new(channel: channel).access_token}"
    pedido['Content-Type'] = 'text/plain'
    pedido.body = Base64.strict_encode64(mail.to_s)
    resposta_http = Net::HTTP.start(pedido.uri.host, pedido.uri.port, use_ssl: true, **TEMPO) { |http| http.request(pedido) }
    raise ConversaCanal::RespostaDoConvite::FalhaNoEnvio, "Graph #{resposta_http.code}" unless resposta_http.code.to_i == 202
  end

  def pelo_smtp(mail)
    mail.delivery_method(:smtp, channel.google? ? smtp_do_google : smtp_da_caixa)
    mail.deliver
  end

  def smtp_do_google
    { address: 'smtp.gmail.com', port: 587, user_name: channel.imap_login.presence || channel.email,
      password: Google::RefreshOauthTokenService.new(channel: channel).access_token, domain: 'smtp.gmail.com',
      authentication: 'xoauth2', enable_starttls_auto: true, **TEMPO }
  end

  # Os mesmos campos da resposta da conversa (ConversationReplyMailerHelper#set_delivery_method).
  def smtp_da_caixa
    { address: channel.smtp_address, port: channel.smtp_port, user_name: channel.smtp_login, password: channel.smtp_password,
      domain: channel.smtp_domain, tls: channel.smtp_enable_ssl_tls, enable_starttls_auto: channel.smtp_enable_starttls_auto,
      openssl_verify_mode: channel.smtp_openssl_verify_mode, authentication: channel.smtp_authentication, **TEMPO }
  end
end

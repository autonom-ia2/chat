require 'net/http'

# Resposta ao convite pela agenda do Google (#1984). O Gmail põe o convite na agenda da caixa com o mesmo UID do .ics
# (iCalUID); a resposta muda só a situação da própria caixa (attendeesOmitted), e o Google avisa o organizador.
# Docs: events.list (iCalUID), events.patch (attendeesOmitted, sendUpdates).
# -> true quando respondeu; false quando o evento do mesmo organizador não está na agenda (quem chama responde por
# e-mail).
class ConversaCanal::RespostaDoConvite::AgendaGoogle
  API = 'https://www.googleapis.com/calendar/v3/calendars/primary/events'.freeze
  SITUACAO = { 'aceito' => 'accepted', 'talvez' => 'tentative', 'recusado' => 'declined' }.freeze
  TEMPO = { open_timeout: 15, read_timeout: 30 }.freeze

  pattr_initialize [:channel!, :convite!, :resposta!]

  def perform
    evento = achar_evento
    endereco = meu_endereco(evento)
    return false if endereco.nil?

    responder(evento, endereco)
    true
  end

  private

  def achar_evento
    uri = URI(API)
    uri.query = URI.encode_www_form(iCalUID: convite['uid'], showDeleted: false, maxResults: 5)
    corpo = pedir(Net::HTTP::Get.new(uri))
    Array(corpo['items']).find { |item| item['status'] != 'cancelled' && do_organizador?(item) }
  end

  def do_organizador?(item)
    item.dig('organizer', 'email').to_s.downcase == convite.dig('organizador', 'email')
  end

  def responder(evento, endereco)
    uri = URI("#{API}/#{CGI.escape(evento['id'])}")
    uri.query = URI.encode_www_form(sendUpdates: 'all')
    pedido = Net::HTTP::Patch.new(uri)
    pedido['Content-Type'] = 'application/json'
    pedido.body = { attendeesOmitted: true, attendees: [{ email: endereco, responseStatus: SITUACAO.fetch(resposta) }] }.to_json
    pedir(pedido)
  end

  # O endereço com que a caixa aparece no evento (self), que pode ser um apelido do e-mail da caixa. Sem ele (convite
  # por grupo, por exemplo), o patch acrescentaria a caixa como convidada nova e avisaria todos: responde por e-mail.
  def meu_endereco(evento)
    Array(evento&.dig('attendees')).find { |pessoa| pessoa['self'] }&.dig('email')
  end

  def pedir(pedido)
    pedido['Authorization'] = "Bearer #{Google::CalendarAccessTokenService.new(channel: channel).access_token}"
    uri = pedido.uri
    resposta_http = Net::HTTP.start(uri.host, uri.port, use_ssl: true, **TEMPO) { |http| http.request(pedido) }
    raise ConversaCanal::RespostaDoConvite::FalhaNoEnvio, "Google Agenda #{resposta_http.code}" unless resposta_http.is_a?(Net::HTTPSuccess)

    JSON.parse(resposta_http.body.presence || '{}')
  end
end

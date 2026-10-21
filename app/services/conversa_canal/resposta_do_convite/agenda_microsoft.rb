require 'net/http'

# Resposta ao convite pela agenda da Microsoft (#1984). O UID do .ics nem sempre é o iCalUId do Graph (convite do
# Google aberto no Outlook ganha outro), então o evento sai do próprio e-mail do convite: a mensagem achada pelo
# Message-ID, com o evento expandido (eventMessage/event). Depois, accept / tentativelyAccept / decline com aviso ao
# organizador (sendResponse). Docs: eventMessage-get ($expand), event-accept.
class ConversaCanal::RespostaDoConvite::AgendaMicrosoft
  API = 'https://graph.microsoft.com/v1.0/me'.freeze
  ACAO = { 'aceito' => 'accept', 'talvez' => 'tentativelyAccept', 'recusado' => 'decline' }.freeze
  TEMPO = { open_timeout: 15, read_timeout: 30 }.freeze

  pattr_initialize [:channel!, :message!, :convite!, :resposta!]

  # -> true quando respondeu avisando o organizador; :sem_aviso quando o organizador pediu para não receber respostas;
  # false quando o evento do mesmo organizador não está na agenda (quem chama responde por e-mail).
  def perform
    evento_id = evento_do_email || evento_pelo_uid
    return false if evento_id.blank?

    responder(evento_id, avisar: true)
    true
  rescue PedidoRecusado => e
    # Organizador que pediu para não receber respostas (responseRequested: false): o Graph recusa o aviso com 400.
    raise ConversaCanal::RespostaDoConvite::FalhaNoEnvio, "Microsoft Graph #{e.message}" unless e.message == '400'

    responder(evento_id, avisar: false)
    :sem_aviso
  end

  PedidoRecusado = Class.new(StandardError)

  private

  def responder(evento_id, avisar:)
    pedido = Net::HTTP::Post.new(URI("#{API}/events/#{CGI.escape(evento_id)}/#{ACAO.fetch(resposta)}"))
    pedido['Content-Type'] = 'application/json'
    pedido.body = { sendResponse: avisar }.to_json
    pedir(pedido, recusa: avisar ? PedidoRecusado : ConversaCanal::RespostaDoConvite::FalhaNoEnvio)
  end

  # Em dois passos: a mensagem pelo Message-ID e, dela, o evento (o $expand do eventMessage é de uma mensagem só).
  def evento_do_email
    message_id = message.content_attributes&.dig('email', 'message_id')
    return if message_id.blank?

    corpo = buscar('messages', "internetMessageId eq '#{odata("<#{message_id}>")}'", '$select' => 'id')
    mensagem_id = Array(corpo['value']).first&.dig('id')
    return if mensagem_id.blank?

    uri = URI("#{API}/messages/#{CGI.escape(mensagem_id)}")
    uri.query = URI.encode_www_form('$expand' => 'microsoft.graph.eventMessage/event($select=id,organizer)')
    evento = pedir(Net::HTTP::Get.new(uri))['event']
    evento['id'] if evento && do_organizador?(evento)
  end

  # Ocorrência de uma série: o UID é o da série inteira; só o próprio e-mail aponta a ocorrência certa.
  def evento_pelo_uid
    return if convite['ocorrencia'].present?

    corpo = buscar('events', "iCalUId eq '#{odata(convite['uid'])}'", '$select' => 'id,organizer')
    Array(corpo['value']).find { |evento| do_organizador?(evento) }&.dig('id')
  end

  # O evento só vale se for do organizador do convite: um convite forjado com o UID de uma reunião real não responde
  # por ela.
  def do_organizador?(evento)
    evento.dig('organizer', 'emailAddress', 'address').to_s.downcase == convite.dig('organizador', 'email')
  end

  def buscar(colecao, filtro, extras)
    uri = URI("#{API}/#{colecao}")
    uri.query = URI.encode_www_form({ '$filter' => filtro, '$top' => 1 }.merge(extras))
    pedir(Net::HTTP::Get.new(uri))
  end

  # Aspas simples dentro de um literal OData se escrevem dobradas.
  def odata(texto)
    texto.to_s.gsub("'", "''")
  end

  def pedir(pedido, recusa: ConversaCanal::RespostaDoConvite::FalhaNoEnvio)
    pedido['Authorization'] = "Bearer #{token}"
    uri = pedido.uri
    resposta_http = Net::HTTP.start(uri.host, uri.port, use_ssl: true, **TEMPO) { |http| http.request(pedido) }
    raise recusa, resposta_http.code.to_s unless resposta_http.is_a?(Net::HTTPSuccess)

    JSON.parse(resposta_http.body.presence || '{}')
  end

  def token
    @token ||= Microsoft::GraphTokenService.new(channel: channel).access_token
  end
end

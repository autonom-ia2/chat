# Leituras do histórico das novas conexões (#1071): capacidade da camada do conector, conversas,
# mensagens, mídia e contatos. Usa o transporte e os erros do Waha::Client.
module Waha::Client::HistoryReads
  def history_source_ids_available?
    version = get('/api/server/version')
    version['chat2youHistorySourceIds'] == 'v1' &&
      version['chat2youHistoryFirstConnectionTimestamp'] == 'v1'
  end

  # ---- CHATS/MENSAGENS ----
  def list_chats(session, limit:, offset:)
    query = URI.encode_www_form(
      limit: limit,
      offset: offset,
      sortBy: 'id',
      sortOrder: 'asc'
    )
    get("/api/#{path_component(session)}/chats?#{query}")
  end

  def list_messages(session, chat_id:, limit:, offset:, before:)
    query = URI.encode_www_form(
      {
        'limit' => limit,
        'offset' => offset,
        'filter.timestamp.lte' => before,
        'sortBy' => 'timestamp',
        'sortOrder' => 'asc',
        'downloadMedia' => false
      }
    )
    get("/api/#{path_component(session)}/chats/#{path_component(chat_id)}/messages?#{query}")
  end

  def get_message(session, chat_id:, message_id:)
    query = URI.encode_www_form(downloadMedia: true)
    path = "/api/#{path_component(session)}/chats/#{path_component(chat_id)}/messages/#{path_component(message_id)}"
    get("#{path}?#{query}")
  end

  def get_lid_mapping(session, chat_id:)
    path = chat_id.end_with?('@lid') ? 'lids' : 'lids/pn'
    get("/api/#{path_component(session)}/#{path}/#{path_component(chat_id)}")
  end

  def download_media(url)
    uri = URI.parse(url)
    base = URI.parse(@base)
    unless [uri.scheme, uri.host, uri.port] == [base.scheme, base.host, base.port] &&
           uri.userinfo.nil? && uri.path.start_with?("#{base.path}/api/files/")
      raise Waha::Client::Error, 'history_media_origin_mismatch'
    end

    limit = GlobalConfigService.load('MAXIMUM_FILE_UPLOAD_SIZE', 40).to_i
    Down.download(url, headers: { 'X-Api-Key' => @key }, max_redirects: 0,
                       max_size: (limit.positive? ? limit : 40).megabytes, open_timeout: 10, read_timeout: 10)
  rescue URI::InvalidURIError
    raise Waha::Client::Error, 'history_media_invalid_url'
  rescue Down::TimeoutError, Down::ConnectionError, Down::ServerError => e
    raise Waha::Client::Error, "history_media_read_failed #{e.class}", cause: nil
  end

  def get_contact(session, contact_id:)
    query = URI.encode_www_form(session: session, contactId: contact_id)
    get("/api/contacts?#{query}")
  end

  private

  def path_component(value)
    URI.encode_www_form_component(value.to_s)
  end
end

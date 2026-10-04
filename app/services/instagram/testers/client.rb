class Instagram::Testers::Client
  HOST = 'https://developers.facebook.com'.freeze
  ROLES_QUERY_NAME = 'RolesTable_Query'.freeze
  TIMEOUT = 10
  TRANSPORT_ERRORS = [Timeout::Error, IOError, EOFError, SocketError, SystemCallError,
                      OpenSSL::SSL::SSLError, Net::ProtocolError, Zlib::Error, HTTParty::Error].freeze

  def initialize(configuration:)
    @configuration = configuration
  end

  def search(username)
    query = URI.encode_www_form(value: "@#{username}")
    document = request("/roles/instagram/typeahead/user/?#{query}", {}, error_code: 'meta_unavailable')
    Instagram::Testers::ResponseParser.candidates(document)
  end

  def status(target_id)
    outcome = Instagram::Testers::InvitationOutcome.new(app_id: @configuration.app_id, target_id: target_id)
    outcome.reconcile do
      document = request('/api/graphql/', {
                           'fb_api_caller_class' => 'RelayModern',
                           'fb_api_req_friendly_name' => ROLES_QUERY_NAME,
                           'doc_id' => @configuration.doc_id,
                           'variables' => { app_id: @configuration.app_id }.to_json
                         }, error_code: 'unknown_status', roles_query: true)
      Instagram::Testers::ResponseParser.status(document, target_id)
    end
  end

  def invite(target_id)
    document = request("/apps/#{@configuration.app_id}/async/instagram/roles/add/", {
                         'role' => Instagram::Testers::ResponseParser::ROLE,
                         'user_id_or_vanitys[0]' => target_id,
                         'reload_on_success' => 'false'
                       }, error_code: 'invite_unknown', write: true)
    success = document['payload']['success'] if document['payload'].is_a?(Hash)
    raise Instagram::Testers::Error, 'invite_rejected' if success == false
    raise Instagram::Testers::Error, 'invite_unknown' unless success == true

    true
  end

  private

  def request(path, form, error_code:, write: false, roles_query: false)
    snapshot = @configuration.session_snapshot
    session = session_for(snapshot)
    response = HTTParty.post("#{HOST}#{path}", **request_options(session, form, roles_query))
    invalidate_session_if_rejected(snapshot, response.code)
    validate_http_status!(response.code, write: write)
    Instagram::Testers::ResponseParser.parse(response.body, error_code: error_code)
  rescue Net::ProtocolError => e
    handle_protocol_error(e, write)
  rescue *TRANSPORT_ERRORS
    raise_request_error(write)
  end

  def request_options(session, form, roles_query)
    form = form.merge('av' => session.fetch('user_id')) if roles_query
    body = base_form(session).merge(form)
    headers = headers(session, roles_query: roles_query)
    @configuration.transport_options.merge(body: body, headers: headers, timeout: TIMEOUT, follow_redirects: false)
  end

  def raise_proxy_error
    raise Instagram::Testers::Error.new('proxy_unavailable'), cause: nil
  end

  def raise_request_error(write)
    raise Instagram::Testers::Error.new(write ? 'invite_unknown' : 'meta_unavailable'), cause: nil
  end

  def session_for(snapshot)
    raise Instagram::Testers::Error, 'meta_session_expired' unless snapshot && snapshot[:session]

    snapshot.fetch(:session)
  end

  def invalidate_session_if_rejected(snapshot, status)
    invalidate_session(snapshot, status) if [401, 403].include?(status)
  end

  def handle_protocol_error(error, write)
    return raise_proxy_error if error.respond_to?(:response) && error.response&.code.to_i == 407

    raise_request_error(write)
  end

  def validate_http_status!(status, write:)
    raise Instagram::Testers::Error, 'proxy_unavailable' if status == 407
    raise Instagram::Testers::Error, 'meta_session_expired' if [401, 403].include?(status)
    raise Instagram::Testers::Error, 'rate_limited' if status == 429 && !write
    raise Instagram::Testers::Error, write ? 'invite_unknown' : 'meta_unavailable' unless status == 200
  end

  def invalidate_session(snapshot, status)
    return unless snapshot[:version]

    Instagram::Testers::SessionStore.new(configuration: @configuration).invalidate(version: snapshot[:version], code: "http_#{status}")
  end

  def headers(session, roles_query:)
    headers = {
      'Cookie' => session.fetch('cookie'), 'User-Agent' => session.fetch('user_agent'),
      'X-FB-LSD' => session.fetch('lsd'), 'Origin' => HOST,
      'Referer' => "#{HOST}/apps/#{@configuration.app_id}/roles/roles/?#{URI.encode_www_form(business_id: @configuration.business_id)}",
      'Content-Type' => 'application/x-www-form-urlencoded'
    }
    headers['X-FB-Friendly-Name'] = ROLES_QUERY_NAME if roles_query
    headers
  end

  def base_form(session)
    session.fetch('extra_form', {}).merge(
      '__a' => '1', '__user' => session.fetch('user_id'), 'fb_dtsg' => session.fetch('fb_dtsg'),
      'lsd' => session.fetch('lsd'), 'jazoest' => session.fetch('jazoest'), '__bid' => @configuration.business_id
    )
  end
end

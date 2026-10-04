# Execute only in the approved Rails runtime; input travels through stdin,
# never command arguments, a public endpoint or a repository file.
require 'json'

begin
  input = $stdin.read(2.megabytes + 1)
  raise Instagram::Testers::Error, 'session_update_rejected' if input.bytesize > 2.megabytes

  request = JSON.parse(input)
  configuration = Instagram::Testers::Configuration.new(account_id: '0')
  raise Instagram::Testers::Error, 'session_update_rejected' unless configuration.managed_session? && configuration.proxy.valid?

  store = Instagram::Testers::SessionStore.new(configuration: configuration)
  if request['operation'] == 'version'
    result = { version: store.current_version }
  elsif request['operation'] == 'invalidate'
    raise Instagram::Testers::Error, 'session_update_rejected' unless request['code'] == 'operator_required'

    store.invalidate(version: request['expected_version'], code: 'operator_required')
    result = { version: store.current_version }
  elsif request['operation'] == 'publish'
    document = Instagram::Testers::ResponseParser.parse(request.fetch('roles_response'), error_code: 'unknown_status')
    # A complete observed roles response must pass the same production parser.
    Instagram::Testers::ResponseParser.status(document, '0')
    version = store.publish(session: request.fetch('session'), expected_version: request['expected_version'],
                            captured_at: request.fetch('captured_at'), app_id: request.fetch('app_id'),
                            business_id: request.fetch('business_id'), proxy_fingerprint: request.fetch('proxy_fingerprint'))
    result = { version: version }
  else
    raise Instagram::Testers::Error, 'session_update_rejected'
  end
  $stdout.write(result.to_json)
rescue StandardError
  # Rails/JSON/encryption/Redis exceptions may contain input: suppress them all.
  $stderr.write("Instagram session publication failed\n")
  exit 2
end

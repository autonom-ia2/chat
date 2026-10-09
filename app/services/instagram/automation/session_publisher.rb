# Fixed stdin protocol for the restricted runtime. No executable input is accepted.
class Instagram::Automation::SessionPublisher
  INPUT_KEYS = {
    %w[operator manager_heartbeat] => %w[type operation state control_available],
    %w[operator operator_read] => %w[type operation],
    %w[operator operator_claim] => %w[type operation id],
    %w[operator operator_complete] => %w[type operation id state],
    %w[session bootstrap] => %w[type operation],
    %w[session version] => %w[type operation],
    %w[session publish] => %w[type operation session expected_version captured_at app_id business_id proxy_fingerprint roles_response
                              configuration_revision roles_doc_id]
  }.freeze
  FINGERPRINT = /\A[0-9a-f]{64}\z/
  # Pin every configuration read by SessionStore to the same locked metadata snapshot.
  Snapshot = Struct.new(:app_id, :business_id, :admin_user_id, :proxy_fingerprint, keyword_init: true)

  def call(request)
    validate!(request)
    return operator_result(request) if request.fetch('type') == 'operator'

    configuration = Instagram::Testers::Configuration.new(account_id: '0')
    raise Instagram::Testers::Error, 'session_update_rejected' unless configuration.managed_session? && configuration.proxy.valid?

    with_metadata do |metadata, revision|
      snapshot = Snapshot.new(app_id: metadata.fetch('INSTAGRAM_META_DEVELOPER_APP_ID'),
                              business_id: metadata.fetch('INSTAGRAM_META_BUSINESS_ID'),
                              admin_user_id: metadata.fetch('INSTAGRAM_TESTER_ADMIN_USER_ID'),
                              proxy_fingerprint: configuration.proxy.fingerprint)
      store = Instagram::Testers::SessionStore.new(configuration: snapshot)
      case request.fetch('operation')
      when 'bootstrap' then { type: 'bootstrap', metadata: metadata, revision: revision, version: store.current_version }
      when 'version' then { type: 'session', version: store.current_version }
      else
        validate_configuration!(request, metadata, revision)
        publish(store, request)
      end
    end
  end

  private

  def validate_configuration!(request, metadata, revision)
    matches = request.fetch('configuration_revision') == revision &&
              request.fetch('roles_doc_id') == metadata.fetch('INSTAGRAM_TESTER_ROLES_DOC_ID')
    raise Instagram::Testers::Error, 'session_update_rejected' unless matches
  end

  def with_metadata
    InstallationConfig.transaction do
      # Require saved metadata: the runtime must never bootstrap from stale local ENV IDs.
      # Row locks remain held through the session CAS, fencing concurrent transactional admin edits.
      rows = InstallationConfig.where(name: Instagram::Automation::Metadata::KEYS).reorder(:name).lock.to_a
      metadata = rows.to_h { |row| [row.name, row.value] }
      validate_metadata!(metadata)
      metadata = Instagram::Automation::Metadata::KEYS.index_with { |key| metadata.fetch(key) }
      revision = Digest::SHA256.hexdigest(metadata.to_json)
      yield metadata, revision
    end
  end

  def validate_metadata!(metadata)
    keys = Instagram::Automation::Metadata::KEYS
    valid = metadata.keys.sort == keys.sort && metadata.all? do |key, value|
      Instagram::Automation::Metadata.valid_value?(key, value) && value.bytesize <= 480
    end
    raise Instagram::Testers::Error, 'session_update_rejected' unless valid
  end

  def publish(store, request)
    document = Instagram::Testers::ResponseParser.parse(request.fetch('roles_response'), error_code: 'unknown_status')
    validate_session_response!(document, request.fetch('app_id'))
    publication = lambda do
      store.publish(session: request.fetch('session'), expected_version: request.fetch('expected_version'),
                    captured_at: request.fetch('captured_at'), app_id: request.fetch('app_id'),
                    business_id: request.fetch('business_id'), proxy_fingerprint: request.fetch('proxy_fingerprint'))
    end
    version = if request.key?('request_id')
                Instagram::Automation::OperatorControl.new.with_publication(request.fetch('request_id'), &publication)
              else
                publication.call
              end
    { type: 'session', version: version }
  end

  def validate_session_response!(document, app_id)
    application = document.dig('data', 'fetch__Application')
    if application.is_a?(Hash)
      raise Instagram::Testers::Error, 'unknown_status' unless application['id'].to_s == app_id

      return
    end

    Instagram::Testers::ResponseParser.status(document, '0')
  end

  def operator_result(request)
    control = Instagram::Automation::OperatorControl.new
    case request.fetch('operation')
    when 'manager_heartbeat'
      control.heartbeat(state: request.fetch('state'), control_available: request.fetch('control_available'), request_id: request['request_id'])
    when 'operator_read' then control.read
    when 'operator_claim'
      control.claim(request.fetch('id'))
      control.read
    when 'operator_complete'
      control.complete(request.fetch('id'), request.fetch('state'))
      control.read
    end
  end

  def validate!(request)
    raise Instagram::Automation::OperatorControl::Rejected unless request.is_a?(Hash) && request.keys.sort == expected_keys(request).sort
    raise Instagram::Automation::OperatorControl::Rejected if request.to_json.bytesize > (request['type'] == 'operator' ? 512 : 2.megabytes)

    validate_operator_fields!(request)
    validate_session!(request) if request['operation'] == 'publish'
  end

  def validate_operator_fields!(request)
    %w[id request_id].each { |key| validate_optional_uuid!(request, key) }
    return unless request['operation'] == 'operator_complete'

    raise Instagram::Automation::OperatorControl::Rejected unless %w[operator_required failed].include?(request['state'])
  end

  def expected_keys(request)
    keys = INPUT_KEYS[[request['type'], request['operation']]]
    raise Instagram::Automation::OperatorControl::Rejected unless keys
    return keys unless %w[publish manager_heartbeat].include?(request['operation'])

    request.key?('request_id') ? keys + ['request_id'] : keys
  end

  def validate_session!(request)
    valid = (request['expected_version'].nil? || uuid?(request['expected_version'])) && request['session'].is_a?(Hash) &&
            %w[captured_at app_id business_id proxy_fingerprint roles_response roles_doc_id configuration_revision].all? do |key|
              request[key].is_a?(String)
            end &&
            request['configuration_revision'].match?(FINGERPRINT)
    raise Instagram::Automation::OperatorControl::Rejected unless valid
  end

  def validate_optional_uuid!(request, key)
    raise Instagram::Automation::OperatorControl::Rejected if request.key?(key) && !uuid?(request[key])
  end

  def uuid?(value)
    value.is_a?(String) && value.match?(Instagram::Automation::OperatorControl::UUID)
  end
end

# Fixed stdin protocol for the restricted runtime. No executable input is accepted.
# Keep the stdin protocol validators together so every publisher reply is bounded
# before it reaches the browser transport.
# rubocop:disable Metrics/ClassLength -- session and browser envelopes share one protocol boundary
class Instagram::Automation::SessionPublisher
  INPUT_KEYS = {
    %w[operator manager_heartbeat] => %w[type operation state control_available],
    %w[operator operator_read] => %w[type operation],
    %w[operator operator_claim] => %w[type operation id],
    %w[operator operator_complete] => %w[type operation id state],
    %w[browser_operation read] => %w[type operation],
    %w[browser_operation claim] => %w[type operation id request_id],
    %w[browser_operation invite_permit] => %w[type operation id request_id claim captured_at target_id username status],
    %w[session bootstrap] => %w[type operation],
    %w[session version] => %w[type operation],
    %w[session publish] => %w[type operation session expected_version captured_at app_id business_id proxy_fingerprint roles_response
                              configuration_revision roles_doc_id]
  }.freeze
  BROWSER_COMPLETE_KEYS = %w[type operation action id request_id claim captured_at].freeze
  BROWSER_ACTIONS = %w[search status authorization invite].freeze
  BROWSER_ROLE_ACTIONS = %w[status authorization invite].freeze
  BROWSER_STATUS_VALUES = %w[absent pending accepted].freeze
  BROWSER_TIMESTAMP = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\z/
  FINGERPRINT = /\A[0-9a-f]{64}\z/
  # Pin every configuration read by SessionStore to the same locked metadata snapshot.
  Snapshot = Struct.new(:app_id, :business_id, :admin_user_id, :proxy_fingerprint, keyword_init: true)

  def call(request)
    validate!(request)
    return operator_result(request) if request.fetch('type') == 'operator'
    return browser_operation_result(request) if request.fetch('type') == 'browser_operation'

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
    Instagram::Testers::ResponseParser.status(document, '0')
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

  def browser_operation_result(request)
    operations = Instagram::Testers::BrowserOperations.new
    case request.fetch('operation')
    when 'read'
      { type: 'browser_operation', operation: 'read', request: operations.next_request }
    when 'claim'
      claimed = operations.claim(id: request.fetch('id'), request_id: request.fetch('request_id'))
      { type: 'browser_operation', operation: 'claim', request: claimed }
    when 'invite_permit'
      invite_permit_result(operations, request)
    when 'complete'
      completed = operations.complete!(request)
      response = { type: 'browser_operation', operation: 'complete', id: completed.fetch('id'),
                   request_id: completed.fetch('request_id'), state: completed.fetch('state') }
      response[:error_code] = browser_reply_error_code(request, completed) if completed.key?('error_code')
      response
    end
  end

  def validate!(request)
    raise Instagram::Automation::OperatorControl::Rejected unless request.is_a?(Hash) && request.keys.sort == expected_keys(request).sort
    raise Instagram::Automation::OperatorControl::Rejected if request.to_json.bytesize > (request['type'] == 'operator' ? 512 : 2.megabytes)

    validate_operator_fields!(request)
    validate_browser_operation!(request) if request['type'] == 'browser_operation'
    validate_session!(request) if request['operation'] == 'publish'
  end

  def validate_operator_fields!(request)
    %w[id request_id].each { |key| validate_optional_uuid!(request, key) }
    return unless request['operation'] == 'operator_complete'

    raise Instagram::Automation::OperatorControl::Rejected unless %w[operator_required failed].include?(request['state'])
  end

  def expected_keys(request)
    return browser_complete_keys(request) if request['type'] == 'browser_operation' && request['operation'] == 'complete'

    keys = INPUT_KEYS[[request['type'], request['operation']]]
    raise Instagram::Automation::OperatorControl::Rejected unless keys
    return keys unless %w[publish manager_heartbeat].include?(request['operation'])

    request.key?('request_id') ? keys + ['request_id'] : keys
  end

  def browser_complete_keys(request)
    action = request['action']
    if request.key?('error_code')
      return BROWSER_COMPLETE_KEYS + %w[target_id error_code write_started] if action == 'invite'
      return BROWSER_COMPLETE_KEYS + ['error_code'] if BROWSER_ACTIONS.include?(action)

      raise Instagram::Automation::OperatorControl::Rejected
    end
    return BROWSER_COMPLETE_KEYS + ['results'] if action == 'search'
    return BROWSER_COMPLETE_KEYS + %w[target_id status invited write_started] if action == 'invite'
    return BROWSER_COMPLETE_KEYS + %w[target_id status] if BROWSER_ROLE_ACTIONS.include?(action)

    raise Instagram::Automation::OperatorControl::Rejected
  end

  def validate_browser_operation!(request) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity -- exact envelope validation is intentionally fail-closed
    case request.fetch('operation')
    when 'read'
      true
    when 'claim'
      validate_browser_uuid!(request.fetch('id'))
      validate_browser_uuid!(request.fetch('request_id'))
    when 'invite_permit'
      validate_browser_uuid!(request.fetch('id'))
      validate_browser_uuid!(request.fetch('request_id'))
      validate_browser_uuid!(request.fetch('claim'))
      validate_browser_timestamp!(request.fetch('captured_at'))
      raise Instagram::Automation::OperatorControl::Rejected unless Instagram::Testers::Validation.id?(request.fetch('target_id'))
      raise Instagram::Automation::OperatorControl::Rejected unless Instagram::Testers::Validation.username?(request.fetch('username'))
      raise Instagram::Automation::OperatorControl::Rejected unless request.fetch('status') == 'absent'
    when 'complete'
      validate_browser_uuid!(request.fetch('id'))
      validate_browser_uuid!(request.fetch('request_id'))
      validate_browser_uuid!(request.fetch('claim'))
      validate_browser_timestamp!(request.fetch('captured_at'))
      if request.key?('error_code')
        validate_browser_error_code!(request.fetch('error_code'))
        if request.fetch('action') == 'invite'
          raise Instagram::Automation::OperatorControl::Rejected unless Instagram::Testers::Validation.id?(request.fetch('target_id'))
          raise Instagram::Automation::OperatorControl::Rejected unless [true, false].include?(request.fetch('write_started'))
        end
        return
      end
      if request.fetch('action') == 'search'
        validate_browser_results!(request.fetch('results'))
      elsif request.fetch('action') == 'invite'
        raise Instagram::Automation::OperatorControl::Rejected unless Instagram::Testers::Validation.id?(request.fetch('target_id'))
        raise Instagram::Automation::OperatorControl::Rejected unless %w[pending accepted].include?(request.fetch('status'))
        raise Instagram::Automation::OperatorControl::Rejected unless [true, false].include?(request.fetch('invited'))
        raise Instagram::Automation::OperatorControl::Rejected unless [true, false].include?(request.fetch('write_started'))
        raise Instagram::Automation::OperatorControl::Rejected unless request.fetch('invited') == request.fetch('write_started')
        raise Instagram::Automation::OperatorControl::Rejected if request.fetch('invited') && request.fetch('status') != 'pending'
      else
        raise Instagram::Automation::OperatorControl::Rejected unless BROWSER_ROLE_ACTIONS.include?(request.fetch('action'))
        raise Instagram::Automation::OperatorControl::Rejected unless Instagram::Testers::Validation.id?(request.fetch('target_id'))
        raise Instagram::Automation::OperatorControl::Rejected unless BROWSER_STATUS_VALUES.include?(request.fetch('status'))
      end
    else
      raise Instagram::Automation::OperatorControl::Rejected
    end
  rescue KeyError, TypeError
    raise Instagram::Automation::OperatorControl::Rejected
  end

  def validate_browser_results!(results) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- every candidate field is validated before materialization
    raise Instagram::Automation::OperatorControl::Rejected unless results.is_a?(Array) && results.length <= 100

    results.each do |candidate|
      valid = candidate.is_a?(Hash) && candidate.keys.sort == %w[avatar_url id name username] &&
              Instagram::Testers::Validation.id?(candidate['id']) &&
              Instagram::Testers::Validation.username?(candidate['username']) &&
              candidate['name'].is_a?(String) && candidate['name'].length <= 500 &&
              Instagram::Testers::Validation.avatar?(candidate['avatar_url'])
      raise Instagram::Automation::OperatorControl::Rejected unless valid
    end
  end

  def validate_browser_uuid!(value)
    raise Instagram::Automation::OperatorControl::Rejected unless uuid?(value)
  end

  # invite_not_sent is a Rails conclusion for the UI: only Rails can prove the
  # claim was released, and the browser validates replies against its own codes.
  # The browser therefore never sends it and gets back the code it sent.
  def validate_browser_error_code!(value)
    valid = value.is_a?(String) && value != 'invite_not_sent' && Instagram::Testers::Error::STATUSES.key?(value)
    raise Instagram::Automation::OperatorControl::Rejected unless valid
  end

  def browser_reply_error_code(request, completed)
    code = completed.fetch('error_code')
    code == 'invite_not_sent' ? request.fetch('error_code') : code
  end

  def invite_permit_result(operations, request)
    operations.invite_permit(request)
  rescue Instagram::Testers::Error, Instagram::Testers::BrowserOperationStore::Rejected => e
    invite_permit_error(request, e)
  rescue StandardError
    invite_permit_error(request, nil)
  end

  def invite_permit_error(request, error)
    code = error.respond_to?(:code) ? error.code : nil
    code = 'invite_unknown' unless Instagram::Testers::Error::STATUSES.key?(code)
    { type: 'browser_operation', operation: 'invite_permit', id: request.fetch('id'),
      request_id: request.fetch('request_id'), claim: request.fetch('claim'), error_code: code }
  end

  def validate_browser_timestamp!(value)
    valid = value.is_a?(String) && BROWSER_TIMESTAMP.match?(value) && Time.iso8601(value).utc.iso8601(3) == value
    raise Instagram::Automation::OperatorControl::Rejected unless valid
  rescue ArgumentError
    raise Instagram::Automation::OperatorControl::Rejected
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
# rubocop:enable Metrics/ClassLength

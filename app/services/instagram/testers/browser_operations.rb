# Keep enqueue, claim and completion together so the same service owns the browser
# operation lifecycle and its fresh authorization checks.
# rubocop:disable Metrics/ClassLength -- lifecycle and validation share one fail-closed boundary
class Instagram::Testers::BrowserOperations
  STATUS_VALUES = %w[absent pending accepted].freeze
  INVITE_COMPLETION_STATUSES = %w[pending accepted].freeze
  SEARCH_RESULT_KEYS = %w[id username name avatar_url].freeze

  def initialize(store: Instagram::Testers::BrowserOperationStore.new)
    @store = store
  end

  def enqueue_search(account_id:, actor_id:, username:, request_id: nil)
    ensure_runtime_enabled!
    configuration = available_configuration!(account_id)
    Instagram::Testers::RateLimiter.check!(account_id: account_id, actor_id: actor_id)
    normalized = Instagram::Testers::Validation.normalize_username(username)
    @store.enqueue(action: 'search', account_id: account_id, actor_id: actor_id, app_id: configuration.app_id,
                   installation: Instagram::Testers::OauthBinding.installation, request_id: request_id,
                   input: { 'username' => normalized })
  end

  def enqueue_status(account_id:, actor_id:, selection_token:, request_id: nil)
    enqueue_selected('status', account_id: account_id, actor_id: actor_id, selection_token: selection_token,
                               request_id: request_id)
  end

  def enqueue_authorization(account_id:, actor_id:, selection_token:, return_to: nil, request_id: nil)
    enqueue_selected('authorization', account_id: account_id, actor_id: actor_id, selection_token: selection_token,
                                      return_to: return_to, request_id: request_id)
  end

  def enqueue_invite(account_id:, actor_id:, selection_token:, request_id: nil)
    enqueue_selected('invite', account_id: account_id, actor_id: actor_id, selection_token: selection_token,
                               request_id: request_id)
  end

  def next_request
    @store.next_request
  end

  def claim(id:, request_id:)
    claimed = @store.claim(id: id, request_id: request_id)
    operation = @store.claimed(id: id, request_id: request_id, claim: claimed.fetch('claim'))
    validate_execution_context!(operation)
    claimed
  rescue Instagram::Testers::BrowserOperationStore::Rejected
    raise
  rescue Instagram::Testers::Error => e
    complete_claim_failure(claimed, e.code) if claimed
    raise
  rescue StandardError => e
    complete_claim_failure(claimed, 'meta_unavailable') if claimed
    raise Instagram::Testers::Error.new('meta_unavailable'), cause: e
  end

  def invite_permit(request)
    operation = @store.claimed(id: request.fetch('id'), request_id: request.fetch('request_id'), claim: request.fetch('claim'))
    raise Instagram::Testers::Error, 'invalid_selection' unless operation.fetch('action') == 'invite'

    validate_capture!(operation, request.fetch('captured_at'))
    validate_invite_target!(request, operation)
    raise Instagram::Testers::Error, 'invalid_selection' unless request.fetch('status') == 'absent'

    validate_execution_context!(operation)
    outcome = invitation_outcome(operation)
    return invite_permit_response(request, decision: 'noop', status: 'pending') if outcome.state == 'pending'
    raise Instagram::Testers::Error, 'invite_unknown' unless outcome.state.nil?

    outcome.claim!(token: request.fetch('claim'))
    invite_permit_response(request, decision: 'write', status: 'absent')
  end

  def result(id:, account_id:, actor_id:)
    @store.result(id: id, account_id: account_id, actor_id: actor_id)
  end

  # Completes a typed browser observation. The browser never supplies OAuth
  # state or a provider response; only the normalized observation crosses this
  # boundary. BrowserAuthorization owns the final URL construction.
  def complete!(request) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity -- terminal browser states are reconciled in one CAS path
    operation = @store.claimed(id: request.fetch('id'), request_id: request.fetch('request_id'),
                               claim: request.fetch('claim'))
    action = request.fetch('action')
    return complete_failure(request, 'invalid_selection') unless action == operation.fetch('action')

    validate_capture!(operation, request.fetch('captured_at'))
    if request.key?('error_code')
      error_code = request.fetch('error_code')
      raise Instagram::Testers::Error, 'session_update_rejected' unless Instagram::Testers::Error::STATUSES.key?(error_code)

      return complete_invite_error(request, operation) if action == 'invite'

      validate_execution_context!(operation, require_available: false)
      return complete_failure(request, error_code)
    end
    validate_execution_context!(operation)
    case action
    when 'search' then complete_search(request, operation)
    when 'status' then complete_status(request, operation)
    when 'authorization' then complete_authorization(request, operation)
    when 'invite' then complete_invite(request, operation)
    else complete_failure(request, 'session_update_rejected')
    end
  rescue Instagram::Testers::Error => e
    return complete_invite_exception(request, operation, e) if operation && request['action'] == 'invite'

    complete_failure(request, e.code)
  rescue Instagram::Testers::BrowserOperationStore::Rejected
    raise
  rescue StandardError
    if operation && request['action'] == 'invite'
      return complete_invite_exception(request, operation, Instagram::Testers::Error.new('meta_unavailable'))
    end

    complete_failure(request, 'meta_unavailable')
  end

  private

  def enqueue_selected(action, account_id:, actor_id:, selection_token:, return_to: nil, request_id: nil) # rubocop:disable Metrics/ParameterLists -- selection pins must enter together
    ensure_runtime_enabled!
    configuration = available_configuration!(account_id)
    Instagram::Testers::RateLimiter.check!(account_id: account_id, actor_id: actor_id)
    selection = verify_selection!(account_id, actor_id, configuration.app_id, selection_token)
    @store.enqueue(action: action, account_id: account_id, actor_id: actor_id, app_id: configuration.app_id,
                   installation: selection.fetch('installation'), request_id: request_id, selection: selection,
                   return_to: return_to)
  end

  def available_configuration!(account_id)
    configuration = Instagram::Testers::Configuration.new(account_id: account_id)
    configuration.ensure_available!
    configuration
  end

  def ensure_runtime_enabled!
    raise Instagram::Testers::Error, 'not_enabled' unless Instagram::Testers::BrowserOperationStore.runtime_enabled?
  end

  def verify_selection!(account_id, actor_id, app_id, token)
    selection = Instagram::Testers::Selection.new(account_id: account_id, actor_id: actor_id, app_id: app_id).verify(token)
    raise Instagram::Testers::Error, 'invalid_selection' unless selection['app_id'] == app_id

    selection
  end

  def validate_execution_context!(operation, require_available: true) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity -- fresh account, ACL and configuration checks are one boundary
    account_id = operation.fetch('account_id')
    actor_id = operation.fetch('actor_id')
    configuration = Instagram::Testers::Configuration.new(account_id: account_id)

    Account.uncached do
      account = Account.find_by(id: account_id)
      membership = account&.account_users&.lock&.find_by(user_id: actor_id)
      authorized = account&.active? && membership && membership.permission_granted?('inbox_manage')
      if authorized
        context = { user: membership.user, account: account, account_user: membership }
        authorized = InboxPolicy.new(context, Inbox).create?
      end
      raise Instagram::Testers::Error, 'forbidden' unless authorized

      if require_available
        configuration.ensure_available!
      else
        raise Instagram::Testers::Error, 'not_enabled' unless configuration.enabled?
      end
    end

    raise Instagram::Testers::Error, 'invalid_selection' unless configuration.app_id == operation.fetch('app_id')
    raise Instagram::Testers::Error, 'invalid_selection' unless Instagram::Testers::OauthBinding.installation == operation.fetch('installation')
  end

  def validate_capture!(operation, captured_at)
    captured = Time.iso8601(captured_at)
    created = Time.iso8601(operation.fetch('created_at'))
    deadline = Time.iso8601(operation.fetch('deadline'))
    valid = captured.between?(created, deadline) &&
            captured <= Time.current.utc + Instagram::Testers::BrowserOperationStore::CLOCK_SKEW
    raise Instagram::Testers::Error, 'meta_unavailable' unless valid
  rescue ArgumentError, TypeError
    raise Instagram::Testers::Error, 'meta_unavailable'
  end

  def validate_invite_target!(request, operation)
    selection = operation.fetch('selection')
    valid = request.fetch('target_id') == selection.fetch('id') && request.fetch('username') == selection.fetch('username')
    raise Instagram::Testers::Error, 'invalid_selection' unless valid
  rescue KeyError
    raise Instagram::Testers::Error, 'invalid_selection'
  end

  def invite_permit_response(request, decision:, status:)
    { type: 'browser_operation', operation: 'invite_permit', id: request.fetch('id'),
      request_id: request.fetch('request_id'), claim: request.fetch('claim'), decision: decision, status: status }
  end

  def invitation_outcome(operation)
    Instagram::Testers::InvitationOutcome.new(app_id: operation.fetch('app_id'), target_id: operation.dig('selection', 'id'))
  end

  def complete_search(request, operation)
    results = request.fetch('results')
    raise Instagram::Testers::Error, 'meta_unavailable' unless results.is_a?(Array) && results.length <= 100

    selection = Instagram::Testers::Selection.new(account_id: operation.fetch('account_id'),
                                                  actor_id: operation.fetch('actor_id'), app_id: operation.fetch('app_id'))
    candidates = results.map { |candidate| materialize_candidate(candidate, selection) }
    raise Instagram::Testers::Error, 'meta_unavailable' unless candidates.pluck(:id).uniq.length == candidates.length

    complete(request, result: { 'results' => candidates })
  end

  def complete_status(request, operation)
    status, target_id = role_observation(request, operation)
    status = reconcile_status(operation, target_id, status)
    complete(request, result: { 'status' => status })
  end

  def complete_authorization(request, operation)
    status, target_id = role_observation(request, operation)
    status = reconcile_status(operation, target_id, status)
    return complete_failure(request, 'invalid_selection') unless status == 'accepted'

    result = Instagram::Testers::BrowserAuthorization.new.perform(
      account_id: operation.fetch('account_id'), actor_id: operation.fetch('actor_id'),
      selected: operation.fetch('selection'), return_to: operation['return_to']
    )
    raise Instagram::Testers::Error, 'meta_unavailable' unless result.is_a?(Hash) && result[:success] == true && result[:url].is_a?(String)

    complete(request, result: { 'success' => true, 'url' => result.fetch(:url) })
  end

  def complete_invite(request, operation)
    validate_invite_success!(request, operation)
    outcome = invitation_outcome(operation)
    if request.fetch('write_started')
      raise Instagram::Testers::Error, 'invite_unknown' unless outcome.pending!(token: request.fetch('claim'))
    elsif request.fetch('status') == 'accepted'
      outcome.reconcile { 'accepted' }
    end

    complete(request, result: { 'status' => request.fetch('status'), 'invited' => request.fetch('invited') })
  end

  def complete_invite_error(request, operation)
    validate_invite_error!(request, operation)
    context_error = execution_context_error(operation)
    return complete_invite_context_failure(request, operation, context_error) if context_error

    complete_invite_result_error(request, operation)
  end

  def complete_invite_context_failure(request, _operation, error)
    complete_failure(request, error.code)
  end

  def complete_invite_result_error(request, operation)
    release_error = release_invite_claim(request, operation) if release_invite_claim?(request)
    complete_failure(request, release_error&.code || request.fetch('error_code'))
  end

  def complete_invite_exception(request, _operation, error)
    complete_failure(request, error.code)
  end

  def validate_invite_success!(request, operation)
    status = request.fetch('status')
    invited = request.fetch('invited')
    write_started = request.fetch('write_started')
    valid = [
      request.fetch('target_id') == operation.dig('selection', 'id'),
      INVITE_COMPLETION_STATUSES.include?(status),
      boolean?(invited),
      boolean?(write_started),
      invited == write_started,
      !invited || status == 'pending'
    ].all?
    raise Instagram::Testers::Error, 'session_update_rejected' unless valid
  rescue KeyError, TypeError
    raise Instagram::Testers::Error, 'session_update_rejected'
  end

  def validate_invite_error!(request, operation)
    valid_target = request.fetch('target_id') == operation.dig('selection', 'id')
    valid_code = Instagram::Testers::Error::STATUSES.key?(request.fetch('error_code'))
    valid_write_started = [true, false].include?(request.fetch('write_started'))
    raise Instagram::Testers::Error, 'session_update_rejected' unless valid_target && valid_code && valid_write_started
  rescue KeyError, TypeError
    raise Instagram::Testers::Error, 'session_update_rejected'
  end

  def release_invite_claim(request, operation)
    invitation_outcome(operation).release_claim!(token: request.fetch('claim'))
    nil
  rescue Instagram::Testers::Error, Redis::BaseError, ConnectionPool::TimeoutError
    Instagram::Testers::Error.new('invite_unknown')
  end

  def execution_context_error(operation)
    validate_execution_context!(operation, require_available: false)
    nil
  rescue Instagram::Testers::Error => e
    e
  end

  def release_invite_claim?(request)
    !request.fetch('write_started') || request.fetch('error_code') == 'invite_rejected'
  end

  def boolean?(value)
    [true, false].include?(value)
  end

  def materialize_candidate(candidate, selection) # rubocop:disable Metrics/CyclomaticComplexity -- candidate normalization is fail-closed
    raise Instagram::Testers::Error, 'meta_unavailable' unless candidate.is_a?(Hash) && candidate.keys.sort == SEARCH_RESULT_KEYS

    username = Instagram::Testers::Validation.normalize_username(candidate.fetch('username'))
    name = candidate.fetch('name')
    avatar_url = candidate.fetch('avatar_url')
    valid = name.is_a?(String) && name.length <= 500 && Instagram::Testers::Validation.avatar?(avatar_url)
    raise Instagram::Testers::Error, 'meta_unavailable' unless valid

    normalized = { id: candidate.fetch('id'), username: username, name: name, avatar_url: avatar_url }
    raise Instagram::Testers::Error, 'meta_unavailable' unless Instagram::Testers::Validation.id?(normalized[:id])

    normalized.merge(selection_token: selection.issue(normalized))
  rescue KeyError, TypeError
    raise Instagram::Testers::Error, 'meta_unavailable'
  end

  def role_observation(request, operation)
    status = request.fetch('status')
    target_id = request.fetch('target_id')
    raise Instagram::Testers::Error, 'unknown_status' unless STATUS_VALUES.include?(status)
    raise Instagram::Testers::Error, 'invalid_selection' unless target_id == operation.dig('selection', 'id')

    [status, target_id]
  rescue KeyError
    raise Instagram::Testers::Error, 'unknown_status'
  end

  def reconcile_status(operation, target_id, status)
    Instagram::Testers::InvitationOutcome.new(app_id: operation.fetch('app_id'), target_id: target_id).reconcile { status }
  end

  def complete(request, result:)
    @store.complete(id: request.fetch('id'), request_id: request.fetch('request_id'), claim: request.fetch('claim'),
                    state: 'ready', result: result)
  end

  def complete_failure(request, code)
    @store.complete(id: request.fetch('id'), request_id: request.fetch('request_id'), claim: request.fetch('claim'),
                    state: 'failed', error_code: code)
  end

  def complete_claim_failure(request, code)
    complete_failure(request, code)
  rescue Instagram::Testers::BrowserOperationStore::Rejected
    nil
  end
end
# rubocop:enable Metrics/ClassLength

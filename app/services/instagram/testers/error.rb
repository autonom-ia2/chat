class Instagram::Testers::Error < StandardError
  STATUSES = {
    'invalid_username' => 422, 'invalid_selection' => 422, 'meta_unavailable' => 503,
    'meta_session_expired' => 503, 'unknown_status' => 502, 'invite_rejected' => 422,
    'invite_unknown' => 503, 'rate_limited' => 429, 'forbidden' => 403,
    'not_enabled' => 404, 'busy' => 409, 'proxy_unavailable' => 503,
    'session_update_rejected' => 422, 'operator_required' => 503,
    # Set only by Rails after it released the claim of a write that never started.
    'invite_not_sent' => 503
  }.freeze

  attr_reader :code, :http_status, :write_rejected

  def initialize(code, write_rejected: false)
    @code = code
    @http_status = STATUSES.fetch(code)
    @write_rejected = write_rejected
    super(code)
  end
end

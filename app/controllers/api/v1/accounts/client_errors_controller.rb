# Browser errors written to our own log (#1841): the panel reports a failure it could not show in full
# (ex.: the e-mail editor's save) and it lands as one `[client_error]` line in the Rails log, with the
# account and the user. No external service, no table. The panel sends only what it failed at, the
# status and the stack: never the request, the e-mail body or headers. Read the real lines with
# `docker logs chatwoot-web | grep -F '] [client_error] {'` (the request_id tag comes first; a plain
# grep also matches someone's message quoting the tag in another request's Parameters line).
class Api::V1::Accounts::ClientErrorsController < Api::V1::Accounts::BaseController
  FLOW_MAX = 64
  MESSAGE_MAX = 500
  STACK_MAX = 4000
  HTTP_STATUSES = (100..599)

  def create
    flow = text(:flow).strip
    return head :unprocessable_entity if flow.empty? || flow.length > FLOW_MAX

    Rails.logger.error("[client_error] #{entry(flow).to_json}")
    head :no_content
  end

  private

  def entry(flow)
    {
      account_id: Current.account.id,
      user_id: Current.user&.id,
      flow: flow,
      status: http_status,
      message: text(:message).first(MESSAGE_MAX),
      stack: text(:stack).first(STACK_MAX),
      user_agent: request.user_agent.to_s.first(MESSAGE_MAX)
    }
  end

  # Only a string counts as text: an array or a hash sent instead is dropped, not turned into its inspect.
  def text(key)
    value = params[key]
    value.is_a?(String) ? value : ''
  end

  def http_status
    value = params[:status]
    status = value if value.is_a?(Integer)
    status = Integer(value, 10, exception: false) if value.is_a?(String)
    status if HTTP_STATUSES.cover?(status)
  end
end

class Api::V1::Accounts::Instagram::TestersController < Api::V1::Accounts::BaseController
  before_action :authorize_testers
  before_action :ensure_available, except: [:configuration, :operation]
  before_action :rate_limit, except: [:configuration, :operation], unless: :browser_operations_enabled?

  rescue_from Instagram::Testers::Error, with: :render_tester_error
  rescue_from Instagram::Testers::BrowserOperationStore::Rejected, with: :render_browser_error

  def configuration
    render json: tester_configuration.public_configuration
  end

  def search
    username = Instagram::Testers::Validation.normalize_username(params.permit(:username)[:username])
    if browser_operations_enabled?
      render json: browser_operations.enqueue_search(account_id: Current.account.id, actor_id: current_user.id, username: username),
             status: :accepted
      return
    end

    results = client.search(username).map { |candidate| candidate.merge(selection_token: selection.issue(candidate)) }
    render json: { results: results }
  end

  def status
    if browser_operations_enabled?
      render json: browser_operations.enqueue_status(account_id: Current.account.id, actor_id: current_user.id,
                                                     selection_token: params.permit(:selection_token)[:selection_token]), status: :accepted
      return
    end

    target_id = selected.fetch('id')
    render json: { status: client.status(target_id) }
  end

  def invite
    if browser_operations_enabled?
      render json: browser_operations.enqueue_invite(account_id: Current.account.id, actor_id: current_user.id,
                                                     selection_token: params.permit(:selection_token)[:selection_token]), status: :accepted
      return
    end

    target_id = selected.fetch('id')
    result = Instagram::Testers::Invitation.new(client: client, app_id: tester_configuration.app_id, target_id: target_id).perform
    render json: result
  end

  def operation
    render json: browser_operations.result(id: params.permit(:id)[:id], account_id: Current.account.id, actor_id: current_user.id)
  end

  private

  def browser_operations_enabled?
    Instagram::Testers::BrowserOperationStore.runtime_enabled?
  end

  def browser_operations
    @browser_operations ||= Instagram::Testers::BrowserOperations.new
  end

  def render_browser_error(error)
    render_tester_error(Instagram::Testers::Error.new(error.code))
  end

  def authorize_testers
    check_permission_granted!('inbox_manage')
    raise Instagram::Testers::Error, 'forbidden' unless current_user
  rescue Pundit::NotAuthorizedError
    raise Instagram::Testers::Error.new('forbidden'), cause: nil
  end

  def tester_configuration
    @tester_configuration ||= Instagram::Testers::Configuration.new(account_id: Current.account.id)
  end

  def ensure_available
    tester_configuration.ensure_available!
  end

  def rate_limit
    Instagram::Testers::RateLimiter.check!(account_id: Current.account.id, actor_id: current_user.id)
  end

  def client
    @client ||= Instagram::Testers::Client.new(configuration: tester_configuration)
  end

  def selection
    @selection ||= Instagram::Testers::Selection.new(account_id: Current.account.id, actor_id: current_user.id, app_id: tester_configuration.app_id)
  end

  def selected
    selection.verify(params.permit(:selection_token)[:selection_token])
  end

  def render_tester_error(error)
    render json: { error_code: error.code }, status: error.http_status
  end
end

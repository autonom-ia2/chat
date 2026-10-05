class Api::V1::Accounts::Instagram::TestersController < Api::V1::Accounts::BaseController
  before_action :authorize_testers
  before_action :ensure_available, except: :configuration
  before_action :rate_limit, except: :configuration

  rescue_from Instagram::Testers::Error, with: :render_tester_error

  def configuration
    render json: tester_configuration.public_configuration
  end

  def search
    username = Instagram::Testers::Validation.normalize_username(params.permit(:username)[:username])
    results = client.search(username).map { |candidate| candidate.merge(selection_token: selection.issue(candidate)) }
    render json: { results: results }
  end

  def status
    target_id = selected.fetch('id')
    render json: { status: client.status(target_id) }
  end

  def invite
    target_id = selected.fetch('id')
    result = Instagram::Testers::Invitation.new(client: client, app_id: tester_configuration.app_id, target_id: target_id).perform
    render json: result
  end

  private

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

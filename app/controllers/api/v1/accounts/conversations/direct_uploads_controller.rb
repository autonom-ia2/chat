class Api::V1::Accounts::Conversations::DirectUploadsController < ActiveStorage::DirectUploadsController
  include DeviseTokenAuth::Concerns::SetUserByToken
  include RequestExceptionHandler
  include AccessTokenAuthHelper
  include EnsureCurrentAccountHelper

  skip_before_action :verify_authenticity_token, if: :authenticate_by_access_token?

  around_action :handle_with_exception
  before_action :authenticate_access_token!, if: :authenticate_by_access_token?
  before_action :validate_bot_access_token!, if: :authenticate_by_access_token?
  before_action :authenticate_user!, unless: :authenticate_by_access_token?
  before_action :current_account
  before_action :validate_token_api_access, if: :authenticate_by_access_token?
  before_action :conversation

  def create
    return if @current_account.nil?

    super
  end

  private

  def authenticate_by_access_token?
    request.headers[:api_access_token].present? || request.headers[:HTTP_API_ACCESS_TOKEN].present?
  end

  def validate_token_api_access
    return if Current.account.api_and_webhooks_enabled?

    render json: { error: 'API access is not enabled for this account' }, status: :forbidden
  end

  def conversation
    # Conversa que não existe responde 404, como as outras rotas da conversa (find_by!).
    @conversation ||= Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize_conversation
  end

  # Mesma regra das outras rotas da conversa (Conversations::BaseController): subir arquivo é escrita, segue em show?, e a
  # recusa vira 401 no handle_with_exception (#2147). Este controller não herda o ApplicationController: o contexto do
  # Pundit é montado aqui, igual ao pundit_user de lá. Na sessão quem responde é o current_user do Devise.
  def authorize_conversation
    user_context = { user: Current.user || current_user, account: Current.account, account_user: Current.account_user }
    Pundit.authorize(user_context, @conversation, :show?)
  end
end

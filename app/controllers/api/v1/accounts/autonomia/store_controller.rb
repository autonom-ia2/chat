# frozen_string_literal: true

class Api::V1::Accounts::Autonomia::StoreController < Api::V1::Accounts::BaseController
  before_action :ensure_super_admin
  before_action :ensure_auth_session
  before_action :fetch_target, except: [:catalog, :features]

  rescue_from Autonomia::Financial::StoreClientError, with: :render_store_error
  rescue_from Autonomia::Financial::StoreContractError, with: :render_invalid_request

  def catalog
    page = pagination_integer(:page, 1)
    page_size = pagination_integer(:page_size, 20)
    render json: store_client.catalog!(page: page, page_size: page_size)
  end

  def agent_services
    render json: store_client.agent_services!(@principal.id)
  end

  def features
    render json: { data: ::Autonomia::Financial::StoreFeatures::KEYS }
  end

  def feature_services
    render json: store_client.feature_services!(@target.fetch('featureKey'))
  end

  def create_service
    body = request_body('name', 'description', 'idempotencyKey')
    payload = body.merge('group' => @target.fetch('type'), 'target' => @target)
    ::Autonomia::Financial::StorePublicationContract.validate!('serviceDraftRequest', payload)
    render json: store_client.create_service!(payload), status: :created
    audit_event('draft_created')
  end

  def publication
    render json: store_client.publication!(params[:service_id], target: @target)
  end

  def publish
    body = request_body('status', 'displayOrder')
    payload = body.merge('group' => @target.fetch('type'), 'target' => @target)
    ::Autonomia::Financial::StorePublicationContract.validate!('publicationRequest', payload)
    render json: store_client.publish!(params[:service_id], payload)
    audit_event('publication_updated')
  end

  private

  def ensure_super_admin
    render json: { error: 'Forbidden.' }, status: :forbidden unless Current.user.is_a?(SuperAdmin)
  end

  def ensure_auth_session
    @authorization_token = ::Autonomia::Sso::TokenStore.authorization_token_for(Current.user)
    return if @authorization_token.present?

    render json: { error: 'Sua sessao do Auth expirou. Saia e entre novamente para acessar o financeiro.' },
           status: :unauthorized
  end

  def fetch_target
    if params[:feature_key].present?
      @target = ::Autonomia::Financial::StoreFeatures.target!(params[:feature_key])
      return
    end
    @principal = ::Autonomia::Agents::Agent.kept.where(account: Current.account, principal_agent_id: nil)
                                           .where("config->>'system_key' IS NULL").find(params[:agent_id])
    @target = { 'type' => 'agent', 'installationId' => store_configuration.namespace.fetch('installationId'), 'principalAgentId' => @principal.id }
  end

  def store_configuration
    @store_configuration ||= ::Autonomia::Financial::StoreConfiguration.new
  end

  def store_client
    @store_client ||= ::Autonomia::Financial::StorePublicationClient.new(
      configuration: store_configuration, authorization_token: @authorization_token,
      subject: ::Autonomia::Financial::StoreIdentity.subject!(@authorization_token)
    )
  end

  def pagination_integer(key, default)
    value = params.fetch(key, default)
    maximum = key == :page_size ? 100 : 100_000
    return value if value.is_a?(Integer) && value.between?(1, maximum)
    return value.to_i if value.is_a?(String) && value.match?(/\A[1-9]\d{0,5}\z/) && value.to_i <= maximum

    raise ::Autonomia::Financial::StoreContractError, ["/#{key}"]
  end

  def request_body(*allowed_keys)
    body = request.request_parameters.except('store', 'controller', 'action')
    raise ::Autonomia::Financial::StoreContractError, ['/'] unless (body.keys - allowed_keys).empty?

    body
  end

  def audit_event(action)
    context = "[autonomia][store] action=#{action} actor_id=#{Current.user.id} account_id=#{Current.account.id}"
    Rails.logger.info("#{context} principal_id=#{@principal&.id} feature=#{@target['featureKey']}")
  end

  def render_store_error(error)
    render json: { error: 'Nao foi possivel concluir a operacao da loja.', code: error.code, outcome: error.outcome }, status: error.status
  end

  def render_invalid_request
    render json: { error: 'Configuracao de loja invalida.', code: 'INVALID_REQUEST' }, status: :unprocessable_entity
  end
end

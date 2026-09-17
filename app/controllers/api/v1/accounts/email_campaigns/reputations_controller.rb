class Api::V1::Accounts::EmailCampaigns::ReputationsController < Api::V1::Accounts::EmailCampaigns::BaseController
  before_action :authorize_reputation

  def show
    state = EmailReputationState.find_by(account_id: Current.account.id)
    protection = ::EmailCampaigns::Guardrail.protection(Current.account)
    payload = ::EmailCampaigns::Reputation::Payload.for_state(state) if state
    payload[:resume_allowed] = false if payload && protection && protection[:kind] != 'reputation'
    render json: { protection: protection, state: payload }
  end

  def history
    render json: { history: EmailReputationAudit.where(account_id: Current.account.id).order(id: :desc).limit(100)
                                                .as_json(only: [:id, :action, :actor_id, :snapshot, :created_at]) }
  end

  def provider_release
    result = ::EmailCampaigns::Reputation::ProviderRelease.new.call(actor: Current.user, reason: params[:reason])
    render json: result
  rescue CustomExceptions::EmailReputationOverride
    render json: { error: 'email_campaign.provider_release_denied' }, status: :unprocessable_entity
  end

  def reevaluate
    render json: { protection: ::EmailCampaigns::Guardrail.reevaluate!(Current.account) }
  end

  def override
    result = ::EmailCampaigns::Reputation::Evaluator.new(Current.account).override!(
      actor: Current.user, reason: params[:reason], duration_seconds: params[:duration_seconds], message_budget: params[:message_budget]
    )
    if result[:protection]
      render json: { error: 'email_campaign.protected', protection: result }, status: :unprocessable_entity
    else
      render json: { protection: result }
    end
  rescue CustomExceptions::EmailReputationOverride
    render json: { error: 'email_campaign.invalid_override' }, status: :unprocessable_entity
  end

  private

  def authorize_reputation
    authorize Current.account, "#{action_name}?", policy_class: EmailReputationPolicy
  end
end

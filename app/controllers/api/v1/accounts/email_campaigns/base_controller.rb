class Api::V1::Accounts::EmailCampaigns::BaseController < Api::V1::Accounts::BaseController
  before_action :ensure_email_campaign_enabled

  helper_method :campaign_presentation

  rescue_from EmailCampaigns::Reports::Parameters::Invalid do |error|
    render json: { error: 'email_campaign.invalid_filter', parameter: error.parameter }, status: :unprocessable_entity
  end

  rescue_from CustomExceptions::EmailReputationConfiguration do |error|
    code = error.message == 'hygiene_configuration_invalid' ? 'hygiene_configuration_invalid' : 'reputation_configuration_invalid'
    render json: { error: 'email_campaign.configuration_invalid',
                   protection: { kind: 'technical', code: code, overridable: false } },
           status: :unprocessable_entity
  end

  private

  def campaign_presentation(campaign)
    @campaign_presenter ||= EmailCampaigns::Presentation::Campaign.new(account: Current.account, actor: Current.user)
    @campaign_presenter.call(campaign)
  end

  def validate_hygiene_configuration
    EmailCampaigns::Presentation::Configuration.hygiene
  end

  # Check scalar shape before strong parameters can silently discard malformed input.
  def report_filter_params(keys)
    keys.each do |key|
      next unless params[key].is_a?(Array) || params[key].is_a?(ActionController::Parameters)

      raise EmailCampaigns::Reports::Parameters::Invalid, key
    end
    params.permit(*keys)
  end

  def ensure_email_campaign_enabled
    return if ::EmailCampaigns::Config.enabled?

    render json: { error: 'email_campaign.disabled' }, status: :not_found
  end
end

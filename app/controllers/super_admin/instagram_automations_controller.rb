class SuperAdmin::InstagramAutomationsController < SuperAdmin::ApplicationController
  helper SuperAdmin::InstagramAutomationHelper
  wrap_parameters false
  protect_from_forgery with: :exception
  before_action :protect_browser_response, only: :browser
  before_action :validate_action_parameters!, only: [:create, :health, :reconnect, :browser]
  rescue_from ActionController::InvalidAuthenticityToken, with: :render_invalid_request
  rescue_from Instagram::Automation::Metadata::InvalidConfiguration, with: :render_invalid_configuration

  def show
    read_local_configuration
    respond_to do |format|
      format.html
      format.json { render json: { metadata: @metadata, status: @status } }
    end
  end

  def create
    metadata = Instagram::Automation::Metadata.new
    submitted = submitted_metadata
    metadata.update!(submitted)
    read_local_configuration
    respond_to do |format|
      format.html { redirect_to super_admin_instagram_automation_path, notice: t('super_admin.instagram_automation.saved') }
      format.json { render json: { metadata: @metadata, status: @status } }
    end
  end

  def health
    read_local_configuration
    respond_to do |format|
      format.html { redirect_to super_admin_instagram_automation_path, notice: t('super_admin.instagram_automation.health_checked') }
      format.json { render json: { metadata: @metadata, status: @status } }
    end
  end

  def reconnect
    raise Instagram::Automation::OperatorControl::Rejected unless ENV.fetch('INSTAGRAM_TESTER_SESSION_SOURCE', 'env') == 'managed'

    request = Instagram::Automation::OperatorControl.new.enqueue(actor_id: current_super_admin.id)
    respond_to do |format|
      format.html { redirect_to super_admin_instagram_automation_path, notice: t('super_admin.instagram_automation.reconnect_queued') }
      format.json { render json: { request: request }, status: :accepted }
    end
  rescue Instagram::Automation::OperatorControl::Rejected
    respond_to do |format|
      format.html do
        redirect_to super_admin_instagram_automation_path,
                    status: :see_other, alert: t('super_admin.instagram_automation.operator_channel_unavailable')
      end
      format.json { render json: { error: 'operator_channel_unavailable' }, status: :service_unavailable }
    end
  end

  def browser
    control = Instagram::Automation::OperatorControl.new.status.fetch(:control)
    @grant = Instagram::Automation::OperatorBrowserTicket.new.call(control: control, actor_id: current_super_admin.id)
    render 'super_admin/instagram_automation/browser', layout: false
  rescue Instagram::Automation::OperatorBrowserTicket::Unavailable
    render plain: t('super_admin.instagram_automation.operator_browser_unavailable'), status: :service_unavailable
  end

  private

  def protect_browser_response
    response.headers['Cache-Control'] = 'no-store'
    response.headers['Referrer-Policy'] = 'strict-origin'
  end

  def validate_action_parameters!
    allowed = %w[controller action format authenticity_token utf8 commit]
    allowed << 'instagram_automation' if action_name == 'create'
    raise Instagram::Automation::Metadata::InvalidConfiguration unless (params.keys - allowed).empty?
  end

  def render_invalid_request
    render_configuration_error('invalid_request')
  end

  def render_invalid_configuration
    render_configuration_error('invalid_configuration')
  end

  def render_configuration_error(code)
    respond_to do |format|
      format.html do
        read_local_configuration
        submitted = params[:instagram_automation]
        if action_name == 'create' && submitted.is_a?(ActionController::Parameters)
          submitted.each do |key, value|
            next unless Instagram::Automation::Metadata::KEYS.include?(key)
            next unless Instagram::Automation::Metadata.valid_value?(key, value, allow_empty: true)

            @metadata = @metadata.merge(key => value)
          end
        end
        @errors = [t("super_admin.instagram_automation.#{code}")]
        render :show, status: :unprocessable_entity
      end
      format.json { render json: { error: code }, status: :unprocessable_entity }
    end
  end

  def submitted_metadata
    submitted = params[:instagram_automation]
    valid = submitted.is_a?(ActionController::Parameters) && (submitted.keys - Instagram::Automation::Metadata::KEYS).empty? &&
            submitted.values.all?(String)
    raise Instagram::Automation::Metadata::InvalidConfiguration, 'invalid_configuration' unless valid

    submitted.permit(*Instagram::Automation::Metadata::KEYS).to_h
  end

  def read_local_configuration
    @metadata = Instagram::Automation::Metadata.new.values
    @status = Instagram::Automation::LocalStatus.new(metadata: @metadata).call
  end
end

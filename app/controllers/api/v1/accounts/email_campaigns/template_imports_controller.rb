# Importar modelo de e-mail (#1099, delivery B): `create` receives the pasted model, the .html/.zip file or the
# address and queues the import (202); `show` is polled by the screen until it is ready or failed, and takes back a
# job that died, answering what blocks the saving from what the job stored; `save` turns a ready import into a template
# in "Meus modelos", checked again on the server. Behind the per-account flag email_template_import (404 while it is
# off) and campaign_manage. Errors are codes the screen explains in one sentence, never the client's markup.
class Api::V1::Accounts::EmailCampaigns::TemplateImportsController < Api::V1::Accounts::EmailCampaigns::BaseController
  FEATURE = 'email_template_import'.freeze
  ERROR_PREFIX = 'email_template_import.'.freeze
  ERROR_STATUS = { in_progress: :conflict, not_ready: :conflict }.freeze
  FIELDS = %i[id status source_kind source_url error_code email_campaign_template_id created_at updated_at].freeze

  before_action :ensure_import_enabled
  before_action :fetch_import, only: [:show, :save]

  rescue_from EmailCampaigns::Import::Error do |error|
    render_error(error.code)
  end

  rescue_from EmailCampaigns::Import::Saver::Blocked do |error|
    render_error(error.code, blocking: error.problems.presence)
  end

  def show
    authorize @import
    @import.recover_if_stalled!
    render json: payload(@import)
  end

  def create
    authorize EmailCampaignTemplateImport
    return render_error(:rate_limited, status: :too_many_requests) if EmailCampaigns::Import::Starter.rate_limited?(Current.account)

    import = EmailCampaigns::Import::Starter.call(account: Current.account, user: Current.user, params: create_params)
    render json: payload(import), status: :accepted
  end

  def save
    authorize @import
    template = EmailCampaigns::Import::Saver.call(@import, name: save_params[:name])
    render json: template.as_json(only: Api::V1::Accounts::EmailCampaigns::TemplatesController::SHOW_FIELDS), status: :created
  end

  private

  def ensure_import_enabled
    return if Current.account.feature_enabled?(FEATURE)

    render json: { error: "#{ERROR_PREFIX}disabled" }, status: :not_found
  end

  def fetch_import
    @import = EmailCampaignTemplateImport.where(account: Current.account).find(params[:id])
  end

  def create_params
    params.permit(:source_kind, :content, :url, :file)
  end

  def save_params
    params.permit(:name)
  end

  def payload(import)
    ready = import.status == 'ready'
    import.as_json(only: FIELDS).merge(
      'report' => import.report.presence,
      'result_mjml' => ready ? import.result_mjml : nil,
      'blocking' => ready ? import.blocking : []
    )
  end

  def render_error(code, status: nil, **extra)
    render json: { error: "#{ERROR_PREFIX}#{code}" }.merge(extra.compact), status: status || ERROR_STATUS.fetch(code, :unprocessable_entity)
  end
end

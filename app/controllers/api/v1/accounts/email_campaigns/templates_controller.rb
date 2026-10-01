class Api::V1::Accounts::EmailCampaigns::TemplatesController < Api::V1::Accounts::EmailCampaigns::BaseController
  # Lightweight list payload for the gallery (NO body — fetched lazily via #show).
  INDEX_FIELDS = [:id, :account_id, :name, :category, :thumbnail_url, :created_at, :updated_at].freeze
  SHOW_FIELDS = (INDEX_FIELDS + [:body_mjml, :body_html]).freeze

  def index
    authorize EmailCampaignTemplate
    scope = template_scope.by_category(params[:category]).order(:category, :name)
    render json: scope.map { |template| template.as_json(only: INDEX_FIELDS).merge(catalog_key: EmailCampaigns::TemplateCatalog.key_for(template)) }
  end

  def show
    template = template_scope.find(params[:id])
    authorize template
    render json: template.as_json(only: SHOW_FIELDS)
  end

  def create
    template = account_scope.new(template_params)
    authorize template
    template.save!
    render json: template.as_json(only: SHOW_FIELDS), status: :created
  end

  def destroy
    # Only own-account templates can be destroyed; global gallery templates are read-only.
    template = account_scope.find(params[:id])
    authorize template
    template.destroy!
    head :no_content
  end

  private

  # Read scope for the gallery: account-owned templates plus shared GLOBAL templates (account_id IS NULL).
  def template_scope
    EmailCampaignTemplate.for_account(Current.account)
  end

  # Write scope: account-owned templates only.
  def account_scope
    EmailCampaignTemplate.where(account: Current.account)
  end

  def template_params
    params.require(:email_template).permit(:name, :body_mjml, :body_html, :category, :thumbnail_url)
  end
end

class Api::V1::Accounts::EmailCampaigns::AiController < Api::V1::Accounts::EmailCampaigns::BaseController
  include DeferInteractiveAi

  before_action :ensure_ai_enabled
  before_action :ensure_ai_credential

  ASSET_PARAMS = %i[kind url signed_id description role video_url poster_url poster_signed_id].freeze
  # Limite do e-mail da tela enviado para o ajuste (mesmo do Generator) — validado já no controller p/
  # rejeitar cedo, sem enfileirar.
  MAX_BASE_MJML_BYTES = 120_000

  # Builder copilot ASSÍNCRONO: enfileira a geração (OpenAI background) e retorna 202 na hora — o
  # SubmitJob/PollJob fazem o trabalho de minutos sem segurar a thread web, persistem o resultado
  # na campanha (durável: o usuário pode sair e voltar) e avisam via ActionCable.
  def generate
    authorize EmailCampaign, :create?
    campaign = EmailCampaign.where(account: Current.account).find(params[:campaign_id])
    if params[:base_mjml].to_s.bytesize > MAX_BASE_MJML_BYTES
      return render json: { error: 'email_campaign.base_mjml_too_large' }, status: :unprocessable_entity
    end

    brand = brand_params
    return if performed?

    EmailCampaigns::Ai::Adjustment.clear(campaign)
    token = campaign.ai_begin!
    EmailCampaigns::Ai::SubmitJob.perform_later(campaign.id, token, generation_params.merge('brand' => brand))
    render json: { ai_status: campaign.ai_status }, status: :accepted
  end

  # Polling de fallback (o caminho feliz é o ActionCable). Estado leve da geração da campanha; num
  # ajuste (#1095) também o antes/depois que o editor mostra para a pessoa aplicar ou descartar.
  def status
    campaign = EmailCampaign.where(account: Current.account).find(params[:id])
    render json: { ai_status: campaign.ai_status, ai_error: campaign.ai_error, ai_completed_at: campaign.ai_completed_at,
                   ai_adjustment: EmailCampaigns::Ai::Adjustment.presented(campaign, campaign.ai_generation_token) }
  end

  # A pessoa aplicou ou descartou o ajuste no editor: a proposta deixa de existir.
  def discard_adjustment
    authorize EmailCampaign, :create?
    campaign = EmailCampaign.where(account: Current.account).find(params[:id])
    EmailCampaigns::Ai::Adjustment.clear(campaign)
    head :no_content
  end

  # A pessoa aplicou o ajuste no editor: a proposta deixa de existir e, se o ajuste usou um site pedido no próprio
  # pedido (#1111), a identidade da campanha passa a ser a dele. Descartar (discard_adjustment) não grava nada.
  def apply_adjustment
    authorize EmailCampaign, :create?
    campaign = EmailCampaign.where(account: Current.account).find(params[:id])
    render json: { brand_identity: EmailCampaigns::Ai::Adjustment.apply(campaign) }
  end

  # Reescrita também roda fora do limite de tempo da requisição web.
  def rewrite
    authorize EmailCampaign, :create?
    defer_interactive_ai('email_rewrite', { text: params[:text].to_s, instruction: params[:instruction].to_s })
  end

  private

  def generation_params
    {
      'brief' => params[:brief].to_s,
      'placeholders' => Array(params[:placeholders]),
      'assets' => permitted_assets,
      'base_mjml' => params[:base_mjml].to_s.presence
    }
  end

  # Identidade visual do e-mail (#1076): o kit escolhido, um site lido só para este e-mail (import), ou
  # a padrão da conta. brand_kit_id="none" gera sem identidade. Com BRAND_KITS_ENABLED desligada, nada.
  def brand_params
    return nil unless BrandKits::Config.enabled?
    return brand_from_import if params[:brand_import_id].present?
    return nil if params[:brand_kit_id] == 'none'

    params[:brand_kit_id].present? ? chosen_kit : default_kit
  end

  def brand_mode
    modes = BrandKits::EmailPalettes::MODES
    modes.include?(params[:brand_mode]) ? params[:brand_mode] : BrandKits::EmailPalettes::DEFAULT_MODE
  end

  def chosen_kit
    kit = BrandKit.where(account: Current.account).live.find_by(id: params[:brand_kit_id])
    kit ? { 'kit_id' => kit.id, 'mode' => brand_mode } : render_brand_error('brand_kit.not_found', :not_found)
  end

  def default_kit
    kit = BrandKit.where(account: Current.account).live.find_by(is_default: true)
    kit && { 'kit_id' => kit.id, 'mode' => brand_mode }
  end

  def brand_from_import
    import = BrandImportJob.where(account: Current.account).find_by(id: params[:brand_import_id])
    return render_brand_error('brand_kit_import.not_ready', :unprocessable_entity) unless import&.succeeded?

    { 'import_id' => import.id, 'mode' => brand_mode }
  end

  def render_brand_error(code, status)
    render json: { error: code }, status: status
    nil
  end

  def permitted_assets
    Array(params[:assets]).map do |asset|
      permitted = asset.respond_to?(:permit) ? asset.permit(*ASSET_PARAMS).to_h : asset.to_h
      permitted.with_indifferent_access
    end
  end

  def ensure_ai_enabled
    return if Crm::Ai::Config.enabled?

    render json: { error: 'ai_disabled' }, status: :unprocessable_entity
  end

  def ensure_ai_credential
    @credential = Crm::Ai::CredentialResolver.new(account: Current.account).resolve
    render json: { error: 'ai_not_configured' }, status: :unprocessable_entity if @credential.blank?
  end
end

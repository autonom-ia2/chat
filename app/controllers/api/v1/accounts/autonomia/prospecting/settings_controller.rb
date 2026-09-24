# A conta ajusta só o que é dela: funil padrão do CRM, cache e pontuação. Chave do Google, provider, limites e o
# interruptor da pesquisa são da plataforma e do superadmin (#683): chegam aqui só como leitura.
class Api::V1::Accounts::Autonomia::Prospecting::SettingsController < Api::V1::Accounts::Autonomia::Prospecting::BaseController
  def show
    render json: { payload: setting_payload(setting) }
  end

  def update
    current_setting = setting
    current_setting.update!(settings_attributes)

    render json: { payload: setting_payload(current_setting) }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  private

  def settings_params
    params.require(:settings).permit(
      :cache_ttl_seconds,
      :default_crm_pipeline_id,
      :default_crm_stage_id,
      :scoring_mode,
      :scoring_profile_id,
      :search_score_mode,
      custom_scoring_weights: Autonomia::Prospecting::ScoringProfile::DEFAULT_WEIGHTS.keys
    )
  end

  def settings_attributes
    settings_params.to_h.symbolize_keys.tap do |attributes|
      attributes[:scoring_profile_id] = nil if attributes[:scoring_mode] == 'custom'
      attributes.delete(:scoring_profile_id) if attributes[:scoring_mode] == 'profile' && attributes[:scoring_profile_id].blank?
      attributes.delete(:search_score_mode) if attributes[:search_score_mode].blank?
    end
  end

  def setting_payload(current_setting)
    current_setting.active_scoring_profile

    current_setting.as_json(
      only: [
        :id, :default_limit, :cache_ttl_seconds, :default_crm_pipeline_id, :default_crm_stage_id,
        :scoring_mode, :scoring_profile_id, :custom_scoring_weights, :created_at, :updated_at
      ]
    ).merge(
      platform_google_places_configured: current_setting.google_places_configured?,
      # Linha que nasceu em mock antes da E0 continua em lead fictício; a tela avisa em vez de mostrar chaves prontas.
      mock_provider: current_setting.provider == 'mock',
      google_maps_browser_api_key: current_setting.google_maps_browser_api_key,
      research_enabled: ::Autonomia::Prospecting::Config.research_enabled?(Current.account),
      ai_credential_configured: ::Autonomia::Prospecting::AiCredential.new(account: Current.account).configured?,
      search_score_mode: current_setting.search_score_mode,
      scoring_profiles: scoring_profiles_payload,
      active_scoring_weights: current_setting.active_scoring_weights,
      usage: usage_payload
    )
  end

  def scoring_profiles_payload
    Autonomia::Prospecting::ScoringProfile.order(default: :desc, name: :asc).map do |profile|
      {
        id: profile.id,
        name: profile.name,
        default: profile.default?,
        weights: profile.weights_with_defaults
      }
    end
  end

  def usage_payload
    {
      daily_used: usage_since(Time.current.beginning_of_day),
      monthly_used: usage_since(Time.current.beginning_of_month)
    }
  end

  def usage_since(period_start)
    searches_scope.where('created_at >= ?', period_start).sum(:consumed_api_units)
  end
end

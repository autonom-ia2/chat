# A conta ajusta só o que é dela: funil padrão do CRM, cache, pontuação e país da busca. Chave do Google, provider, limites e o
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
      :search_country,
      custom_scoring_weights: Autonomia::Prospecting::ScoringProfile::DEFAULT_WEIGHTS.keys
    )
  end

  def settings_attributes
    settings_params.to_h.symbolize_keys.tap do |attributes|
      attributes[:scoring_profile_id] = nil if attributes[:scoring_mode] == 'custom'
      attributes.delete(:scoring_profile_id) if attributes[:scoring_mode] == 'profile' && attributes[:scoring_profile_id].blank?
      attributes.delete(:search_score_mode) if attributes[:search_score_mode].blank?
      attributes.delete(:search_country) if attributes[:search_country].blank?
    end
  end

  def setting_payload(current_setting)
    current_setting.active_scoring_profile

    current_setting.as_json(
      only: [
        :id, :default_limit, :cache_ttl_seconds, :default_crm_pipeline_id, :default_crm_stage_id,
        :scoring_mode, :custom_scoring_weights, :created_at, :updated_at
      ]
    ).merge(
      platform_google_places_configured: current_setting.google_places_configured?,
      # Linha que nasceu em mock antes da E0 continua em lead fictício; a tela avisa em vez de mostrar chaves prontas.
      mock_provider: current_setting.provider == 'mock',
      google_maps_browser_api_key: current_setting.google_maps_browser_api_key,
      research_enabled: ::Autonomia::Prospecting::Config.research_enabled?(Current.account),
      ai_credential_configured: ::Autonomia::Prospecting::AiCredential.new(account: Current.account).configured?,
      search_score_mode: current_setting.search_score_mode,
      search_country: current_setting.search_country,
      search_countries: Autonomia::Prospecting::SearchCountry::ALLOWED,
      scoring_profiles: scoring_profiles_payload(current_setting),
      active_scoring_weights: current_setting.active_scoring_weights,
      usage: usage_payload
    ).merge(score_engine_payload(current_setting))
  end

  # Só os globais e os restritos desta conta (#681). O payload não diz a que outras contas um perfil pertence.
  def scoring_profiles_payload(current_setting)
    orth = orth_engine?(current_setting)
    Autonomia::Prospecting::ScoringProfile.available_to(Current.account).includes(:scoring_profile_accounts)
                                          .order(default: :desc, name: :asc).map do |profile|
      entry = { id: profile.id, name: profile.name, default: profile.default?, weights: profile.weights_with_defaults,
                restricted: profile.scoring_profile_accounts.any? }
      orth ? entry.merge(orth_weights: orth_weights_for(profile.weights_with_defaults, default_profile: profile.default?)) : entry
    end
  end

  # Perfil salvo que o superadmin restringiu a outras contas: a tela mostra o padrão, que é o que a busca usa.
  def payload_scoring_profile_id(current_setting)
    profile = current_setting.scoring_profile
    return current_setting.scoring_profile_id if profile.nil? || profile.available_to?(Current.account)

    current_setting.active_scoring_profile.id
  end

  # A virada é da frente B; aqui só se lê o que ela grava em metadata['score_engine'].
  def orth_engine?(current_setting)
    current_setting.metadata.to_h['score_engine'] == 'orth'
  end

  # Motor da nota por conta (#681): 'legacy' até o superadmin virar a conta para 'orth'. Conta não virada recebe o
  # payload de antes, sem chave nova além do nome do motor.
  def score_engine_payload(current_setting)
    payload = { scoring_profile_id: payload_scoring_profile_id(current_setting), score_engine: 'legacy' }
    return payload unless orth_engine?(current_setting)

    default_profile = current_setting.scoring_mode != 'custom' && current_setting.active_scoring_profile.default?
    payload.merge(score_engine: 'orth',
                  orth_scoring_weights: orth_weights_for(current_setting.active_scoring_weights, default_profile: default_profile))
  end

  # Decisão do Rodrigo (25/09): o perfil padrão passa a ser o do Orth; perfil escolhido e pesos próprios da conta
  # ficam como estão, levados para os 6 componentes.
  def orth_weights_for(legacy_weights, default_profile:)
    return Autonomia::Prospecting::Scoring::OrthScorer::DEFAULT_WEIGHTS if default_profile

    Autonomia::Prospecting::Scoring::WeightMapping.from_legacy(legacy_weights)
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

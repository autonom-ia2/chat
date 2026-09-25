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
    ).merge(score_engine_payload(current_setting), permissions_payload)
  end

  # A tela esconde o que o servidor recusaria (#682): Enviar ao CRM pela mesma regra de authorize_crm_card_create! e
  # Adicionar à campanha pela de authorize_campaign_update!.
  def permissions_payload
    { can_send_to_crm: Pundit.policy!(pundit_user, ::Crm::Card).create?, can_manage_campaigns: campaign_manage? }
  end

  # Só os globais e os restritos desta conta (#681). O payload não diz a que outras contas um perfil pertence.
  def scoring_profiles_payload(current_setting)
    orth = current_setting.orth_score_engine?
    Autonomia::Prospecting::ScoringProfile.available_to(Current.account).includes(:scoring_profile_accounts)
                                          .order(default: :desc, name: :asc).map do |profile|
      entry = { id: profile.id, name: profile.name, default: profile.default?, weights: profile.weights_with_defaults,
                restricted: profile.scoring_profile_accounts.any? }
      orth ? entry.merge(orth_weights: orth_weights_for(profile)) : entry
    end
  end

  # Perfil salvo que o superadmin restringiu a outras contas: a tela mostra o padrão, que é o que a busca usa.
  def payload_scoring_profile_id(current_setting)
    profile = current_setting.scoring_profile
    return current_setting.scoring_profile_id if profile.nil? || profile.available_to?(Current.account)

    current_setting.active_scoring_profile.id
  end

  # Motor da nota por conta (#681): 'legacy' até o superadmin virar a conta para 'orth'. Conta não virada recebe o
  # payload de antes, sem chave nova além do nome do motor. Os pesos da conta virada são os mesmos que a busca usa
  # (Setting#orth_scoring_weights); nil ali é o padrão do Orth.
  def score_engine_payload(current_setting)
    payload = { scoring_profile_id: payload_scoring_profile_id(current_setting), score_engine: current_setting.score_engine }
    return payload unless current_setting.orth_score_engine?

    payload.merge(orth_scoring_weights: current_setting.orth_scoring_weights || Autonomia::Prospecting::Scoring::EffectiveWeights::DEFAULT)
  end

  # Decisão do Rodrigo (25/09): o perfil padrão passa a ser o do Orth; perfil escolhido fica como está, levado para os
  # 6 componentes. Mesma regra de Setting#orth_scoring_weights, aplicada a cada perfil da lista.
  def orth_weights_for(profile)
    return Autonomia::Prospecting::Scoring::EffectiveWeights::DEFAULT if profile.default?

    Autonomia::Prospecting::Scoring::WeightMapping.from_legacy(profile.weights_with_defaults)
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

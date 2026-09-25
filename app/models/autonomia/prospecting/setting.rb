# == Schema Information
#
# Table name: autonomia_prospecting_settings
#
#  id                          :bigint           not null, primary key
#  cache_ttl_seconds           :integer          default(86400), not null
#  custom_scoring_weights      :jsonb            not null
#  daily_limit                 :integer
#  default_limit               :integer          default(20), not null
#  enrichment_enabled          :boolean          default(FALSE), not null
#  google_maps_browser_api_key :string
#  google_places_api_key       :string
#  max_results_per_search      :integer          default(20), not null
#  metadata                    :jsonb            not null
#  monthly_limit               :integer
#  provider                    :string           default("google_places"), not null
#  provider_enabled            :boolean          default(FALSE), not null
#  scoring_mode                :string           default("profile"), not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  account_id                  :bigint           not null
#  default_crm_pipeline_id     :bigint
#  default_crm_stage_id        :bigint
#  scoring_profile_id          :bigint
#
# Indexes
#
#  idx_autonomia_prospecting_settings_default_pipeline  (default_crm_pipeline_id)
#  idx_autonomia_prospecting_settings_default_stage     (default_crm_stage_id)
#  idx_autonomia_prospecting_settings_scoring_profile   (scoring_profile_id)
#  index_autonomia_prospecting_settings_on_account_id   (account_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (default_crm_pipeline_id => crm_pipelines.id) ON DELETE => nullify
#  fk_rails_...  (default_crm_stage_id => crm_pipeline_stages.id) ON DELETE => nullify
#  fk_rails_...  (scoring_profile_id => autonomia_prospecting_scoring_profiles.id) ON DELETE => nullify
#
class Autonomia::Prospecting::Setting < ApplicationRecord
  self.table_name = 'autonomia_prospecting_settings'

  belongs_to :account
  belongs_to :default_crm_pipeline, class_name: 'Crm::Pipeline', optional: true
  belongs_to :default_crm_stage, class_name: 'Crm::PipelineStage', optional: true
  belongs_to :scoring_profile, class_name: 'Autonomia::Prospecting::ScoringProfile', optional: true

  if Chatwoot.encryption_configured?
    encrypts :google_places_api_key
    encrypts :google_maps_browser_api_key
  end

  validates :provider, presence: true
  validates :provider, inclusion: { in: %w[mock google_places] }
  validates :default_limit, numericality: { only_integer: true, greater_than: 0 }
  validates :max_results_per_search, numericality: { only_integer: true, greater_than: 0 }
  validates :daily_limit, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :monthly_limit, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :cache_ttl_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :scoring_mode, inclusion: { in: %w[profile custom] }
  validates :account_id, uniqueness: true
  validate :search_score_mode_must_be_supported
  validate :score_engine_must_be_supported
  validate :search_country_must_be_supported
  validate :custom_scoring_weights_must_be_supported_numbers
  validate :scoring_profile_must_be_available_to_account, if: :scoring_profile_id_changed?
  validate :default_crm_records_must_belong_to_account

  before_validation :normalize_scoring_configuration

  def self.for_account(account)
    find_or_create_by!(account: account)
  end

  # Só ENV: GOOGLE_PLACES_API_KEY, GOOGLE_MAPS_BROWSER_API_KEY, BIGDATACORP_USER e BIGDATACORP_PASSWORD (#679).
  # Nada de InstallationConfig nem GlobalConfigService: este copia a variável para o banco, e ela apareceria no superadmin.
  def self.platform_config(name)
    ENV.fetch(name, nil).presence
  end

  # As chaves do Google são da plataforma (#683) e vêm só de variável de ambiente, que em produção sai do SSM.
  # Não aparecem em tela nenhuma, nem no superadmin. As colunas homônimas ficam no banco, mas deixam de ser lidas.
  def google_places_api_key
    platform_config('GOOGLE_PLACES_API_KEY')
  end

  def google_maps_browser_api_key
    platform_config('GOOGLE_MAPS_BROWSER_API_KEY')
  end

  def google_places_configured?
    google_places_api_key.present?
  end

  def google_maps_browser_configured?
    google_maps_browser_api_key.present?
  end

  # Perfil que o superadmin restringiu a outras contas depois da escolha deixa de valer aqui: a conta cai no padrão (#681).
  def active_scoring_profile
    return scoring_profile if scoring_profile&.available_to?(account)

    Autonomia::Prospecting::ScoringProfile.default_profile
  end

  def active_scoring_weights
    return normalized_custom_scoring_weights if scoring_mode == 'custom'

    active_scoring_profile.weights_with_defaults
  end

  def search_score_mode
    metadata.to_h['search_score_mode'].presence || 'gbp'
  end

  def search_score_mode=(value)
    self.metadata = metadata.to_h.merge('search_score_mode' => normalized_search_score_mode(value))
  end

  # Motor da nota da conta (#681): 'legacy' até o superadmin virar a conta para o Orth. A conta não troca pela API de
  # configurações, que não aceita metadata; só o console do superadmin grava.
  SCORE_ENGINES = %w[legacy orth].freeze

  def score_engine
    metadata.to_h['score_engine'].presence || 'legacy'
  end

  def score_engine=(value)
    self.metadata = metadata.to_h.merge('score_engine' => value.to_s)
  end

  def orth_score_engine?
    score_engine == 'orth'
  end

  # Pesos da nota do Orth (#681, decisão do Rodrigo de 25/09): o que a conta personalizou, e o perfil do catálogo que não
  # é o padrão, ficam como estão, mapeados para os componentes do Orth. O perfil padrão passa a ser o do Orth (nil).
  def orth_scoring_weights
    return Autonomia::Prospecting::Scoring::WeightMapping.from_legacy(active_scoring_weights) if scoring_mode == 'custom'
    return if active_scoring_profile.default?

    Autonomia::Prospecting::Scoring::WeightMapping.from_legacy(active_scoring_profile.weights_with_defaults)
  end

  # País da busca no Google (#677). Sem escolha é o Brasil; valor gravado fora da lista também, com aviso no log.
  def search_country
    stored = metadata.to_h['search_country']
    return Autonomia::Prospecting::SearchCountry::DEFAULT if stored.blank?

    country = Autonomia::Prospecting::SearchCountry.normalize(stored)
    return country if country

    Rails.logger.warn("[Prospecting::Setting] search_country_invalid_stored account_id=#{account_id} search_country=#{stored}")
    Autonomia::Prospecting::SearchCountry::DEFAULT
  end

  def search_country=(value)
    self.metadata = metadata.to_h.merge('search_country' => value.to_s.strip.upcase)
  end

  private

  def platform_config(name)
    self.class.platform_config(name)
  end

  def normalize_scoring_configuration
    self.scoring_mode = scoring_mode.presence || 'profile'
    self.custom_scoring_weights = normalized_custom_scoring_weights
    self.scoring_profile ||= Autonomia::Prospecting::ScoringProfile.default_profile if scoring_mode == 'profile'
  end

  def normalized_custom_scoring_weights
    Autonomia::Prospecting::ScoringProfile::DEFAULT_WEIGHTS.keys.index_with do |key|
      value = custom_scoring_weights.to_h[key].presence || Autonomia::Prospecting::ScoringProfile::DEFAULT_WEIGHTS[key]
      value.to_i
    end
  end

  def custom_scoring_weights_must_be_supported_numbers
    return unless scoring_mode == 'custom'

    normalized_custom_scoring_weights.each do |key, value|
      errors.add(:custom_scoring_weights, "#{key} must be between 0 and 100") unless value.to_i.between?(0, 100)
    end
  end

  # Só na troca de perfil: a conta que já usava um perfil depois restringido continua salvando o resto da configuração.
  def scoring_profile_must_be_available_to_account
    return if scoring_profile.blank? || scoring_profile.available_to?(account)

    errors.add(:base, I18n.t('autonomia.prospecting.errors.scoring_profile_unavailable'))
  end

  def search_score_mode_must_be_supported
    return if %w[gbp general].include?(search_score_mode)

    errors.add(:metadata, 'search_score_mode must be gbp or general')
  end

  def score_engine_must_be_supported
    return if SCORE_ENGINES.include?(score_engine)

    errors.add(:metadata, 'score_engine must be legacy or orth')
  end

  def search_country_must_be_supported
    stored = metadata.to_h['search_country']
    return if stored.blank? || Autonomia::Prospecting::SearchCountry.normalize(stored)

    errors.add(:base, I18n.t('autonomia.prospecting.errors.invalid_search_country'))
  end

  def normalized_search_score_mode(value)
    %w[gbp general].include?(value.to_s) ? value.to_s : 'gbp'
  end

  def default_crm_records_must_belong_to_account
    validate_same_account(:default_crm_pipeline)
    validate_same_account(:default_crm_stage)

    return if default_crm_stage.blank? || default_crm_pipeline.blank?
    return if default_crm_stage.pipeline_id == default_crm_pipeline_id

    errors.add(:default_crm_stage, 'must belong to the selected pipeline')
  end

  def validate_same_account(association_name)
    record = public_send(association_name)
    return if record.blank? || account_id.blank?
    return if record.account_id == account_id

    errors.add(association_name, 'must belong to the same account')
  end
end

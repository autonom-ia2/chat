require Rails.root.join('lib/feature_flag_rollout')

# #1175 — conta nova nasce com as funções que as contas existentes já têm ligadas. Liga só o padrão das contas novas
# (ACCOUNT_LEVEL_FEATURE_DEFAULTS); as contas existentes já estão com as 10 ligadas e não são tocadas. O como está em
# lib/feature_flag_rollout.rb. `companies` fica na coluna `feature_flags`: chega à conta nova porque o
# Autonomia::AccountProvisioningDefaults aplica os padrões por nome por cima do número fixo.
class ContaNovaNasceComAsFlagsDasExistentes < ActiveRecord::Migration[7.2]
  FEATURES = %w[
    data_import
    delayed_automations
    relationships_attributes
    relationships_company_media
    relationships_navigation
    meta_ads_hub
    email_template_import
    whatsapp_templates_journey
    crm_configurar_caixas
    companies
  ].freeze

  def up
    FEATURES.each { |feature| FeatureFlagRollout.padrao!(feature, true) }
    GlobalConfig.clear_cache
  end

  # Volta só o padrão das contas novas. Nenhuma conta é desligada.
  def down
    FEATURES.each { |feature| FeatureFlagRollout.padrao!(feature, false) }
    GlobalConfig.clear_cache
  end
end

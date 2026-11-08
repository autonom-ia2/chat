require Rails.root.join('lib/feature_flag_rollout')

# #2045 — conta nova nasce com as Metas do mês por pessoa (#1991, PR #1997), que o Rodrigo aprovou ligar em 21/10/2026.
# Liga só o padrão das contas novas (ACCOUNT_LEVEL_FEATURE_DEFAULTS): as contas existentes foram ligadas pela
# Orquestração e não são tocadas. Mudar o features.yml não basta, porque o ConfigLoader do deploy roda com
# reconcile_only_new e preserva o `enabled` gravado. O como está em lib/feature_flag_rollout.rb (o mesmo caminho do
# #1977).
class ContaNovaNasceComAsMetas < ActiveRecord::Migration[7.2]
  FEATURES = %w[crm_metas].freeze

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

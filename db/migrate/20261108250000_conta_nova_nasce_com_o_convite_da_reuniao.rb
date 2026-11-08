require Rails.root.join('lib/feature_flag_rollout')

# #1984 — conta nova nasce com o convite de reunião no e-mail (decisão da Orquestração, 20/10/2026).
# Liga só o padrão das contas novas (ACCOUNT_LEVEL_FEATURE_DEFAULTS): as contas existentes ficam como estão (o piloto
# 1/16/18 é ligado pela Orquestração depois do deploy). Mudar o features.yml não basta, porque o ConfigLoader do deploy roda com
# reconcile_only_new e preserva o `enabled` gravado. O como está em lib/feature_flag_rollout.rb (o mesmo caminho do
# #1859 e do #1914).
class ContaNovaNasceComOConviteDaReuniao < ActiveRecord::Migration[7.2]
  FEATURES = %w[convite_da_reuniao].freeze

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

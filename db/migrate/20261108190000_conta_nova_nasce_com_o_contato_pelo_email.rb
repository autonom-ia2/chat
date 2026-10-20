require Rails.root.join('lib/feature_flag_rollout')

# #1927 — conta nova nasce com o contato pelo e-mail (#1813), que o Rodrigo ligou em todas as contas em 20/10/2026.
# Liga só o padrão das contas novas (ACCOUNT_LEVEL_FEATURE_DEFAULTS): as contas existentes foram ligadas pela
# Orquestração e não são tocadas. Mudar o features.yml não basta, porque o ConfigLoader do deploy roda com
# reconcile_only_new e preserva o `enabled` gravado. O como está em lib/feature_flag_rollout.rb (o mesmo caminho do
# #1859 e do #1914).
class ContaNovaNasceComOContatoPeloEmail < ActiveRecord::Migration[7.2]
  FEATURES = %w[contato_pelo_email].freeze

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

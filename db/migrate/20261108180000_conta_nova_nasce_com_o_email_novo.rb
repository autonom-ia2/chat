require Rails.root.join('lib/feature_flag_rollout')

# #1913 — conta nova nasce com o e-mail novo, que o Rodrigo liberou para todas as contas em 19/10/2026. Liga só o
# padrão das contas novas (ACCOUNT_LEVEL_FEATURE_DEFAULTS): as contas existentes são ligadas pela Orquestração e não
# são tocadas. Mudar o features.yml não basta, porque o ConfigLoader do deploy roda com reconcile_only_new e preserva
# o `enabled` gravado. O como está em lib/feature_flag_rollout.rb (o mesmo caminho do #1859).
class ContaNovaNasceComOEmailNovo < ActiveRecord::Migration[7.2]
  FEATURES = %w[
    email_autoria
    conversa_email_nova
    email_lido_sincronizado
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

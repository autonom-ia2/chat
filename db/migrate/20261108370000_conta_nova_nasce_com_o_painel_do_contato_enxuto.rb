require Rails.root.join('lib/feature_flag_rollout')

# #2138 — conta nova nasce com o "Painel do contato enxuto na conversa", que o Rodrigo decidiu em 24/10/2026 ligar na
# conta nova. Liga só o padrão das contas novas (ACCOUNT_LEVEL_FEATURE_DEFAULTS): as contas existentes não são tocadas
# aqui (o piloto 1, 16 e 18 é ligado pela Orquestração depois do deploy). Mudar o features.yml não basta, porque o
# ConfigLoader do deploy roda com reconcile_only_new e preserva o `enabled` gravado. O como está em
# lib/feature_flag_rollout.rb (o mesmo caminho do #2079).
class ContaNovaNasceComOPainelDoContatoEnxuto < ActiveRecord::Migration[7.2]
  FEATURES = %w[painel_contato_enxuto].freeze

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

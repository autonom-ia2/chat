require Rails.root.join('lib/feature_flag_rollout')

# #2253 — conta nova nasce com a lista de conversas nova (lista_quem_espera, #2202/#2211) ligada. As contas que já
# existem foram ligadas em 27/10 pela Orquestração, por psql, com backup; esta migration não toca nenhuma delas.
# Liga só o padrão das contas novas (ACCOUNT_LEVEL_FEATURE_DEFAULTS). Mudar o features.yml não basta, porque o
# ConfigLoader do deploy roda com reconcile_only_new e preserva o `enabled` gravado. O como está em
# lib/feature_flag_rollout.rb.
class ContaNovaNasceComAListaNova < ActiveRecord::Migration[7.2]
  FEATURE = 'lista_quem_espera'.freeze

  def up
    FeatureFlagRollout.padrao!(FEATURE, true)
    GlobalConfig.clear_cache
  end

  # Volta só o padrão das contas novas. Nenhuma conta é desligada.
  def down
    FeatureFlagRollout.padrao!(FEATURE, false)
    GlobalConfig.clear_cache
  end
end

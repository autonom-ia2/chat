require Rails.root.join('lib/feature_flag_rollout')

# #2159 — conta nova nasce com CRM › Arquivados, restaurar e excluir de vez (#2095 / #2096), que o Rodrigo liberou
# para todas as contas (24/10/2026).
# Liga só o padrão das contas novas (ACCOUNT_LEVEL_FEATURE_DEFAULTS): as contas existentes já estão ligadas em
# produção e não são tocadas. Mudar o features.yml não basta, porque o ConfigLoader do deploy roda com
# reconcile_only_new e preserva o `enabled` gravado. O como está em lib/feature_flag_rollout.rb.
class ContaNovaNasceComArquivados < ActiveRecord::Migration[7.2]
  FEATURE = 'crm_arquivados'.freeze

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

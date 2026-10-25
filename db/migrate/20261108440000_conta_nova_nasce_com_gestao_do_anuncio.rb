require Rails.root.join('lib/feature_flag_rollout')

# #2191 — conta nova nasce com Anúncios da Meta - pausar anúncio e post da Página (#2161), que o Rodrigo ligou em
# todas as contas (25/10/2026).
# Liga só o padrão das contas novas (ACCOUNT_LEVEL_FEATURE_DEFAULTS): as contas existentes já estão ligadas em
# produção e não são tocadas. Mudar o features.yml não basta, porque o ConfigLoader do deploy roda com
# reconcile_only_new e preserva o `enabled` gravado. O como está em lib/feature_flag_rollout.rb.
class ContaNovaNasceComGestaoDoAnuncio < ActiveRecord::Migration[7.2]
  FEATURE = 'meta_ads_gestao'.freeze

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

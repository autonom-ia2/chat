require Rails.root.join('lib/feature_flag_rollout')

# #2008 — conta nova nasce com a IA de etapa que arquiva o card que não é negócio (#1922, PR #1970), que o Rodrigo
# liberou para todas as contas (decisão repassada pela Orquestração, 21/10/2026).
# Liga só o padrão das contas novas (ACCOUNT_LEVEL_FEATURE_DEFAULTS): as contas existentes foram ligadas pela
# Orquestração e não são tocadas. Mudar o features.yml não basta, porque o ConfigLoader do deploy roda com
# reconcile_only_new e preserva o `enabled` gravado. O como está em lib/feature_flag_rollout.rb.
class ContaNovaNasceComArquivaLixo < ActiveRecord::Migration[7.2]
  FEATURE = 'crm_ia_arquiva_lixo'.freeze

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

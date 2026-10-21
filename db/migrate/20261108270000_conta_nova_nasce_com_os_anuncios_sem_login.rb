require Rails.root.join('lib/feature_flag_rollout')

# #2002 — conta nova nasce com os Anúncios sem login (#1960: a página de Anúncios mostra o resultado pelo WhatsApp
# oficial quando a conta não tem conexão com o Facebook), que o Rodrigo liberou para todas as contas em 21/10/2026.
# Liga só o padrão das contas novas (ACCOUNT_LEVEL_FEATURE_DEFAULTS): as contas existentes são ligadas pela
# Orquestração e não são tocadas. Mudar o features.yml não basta, porque o ConfigLoader do deploy roda com
# reconcile_only_new e preserva o `enabled` gravado. O como está em lib/feature_flag_rollout.rb.
class ContaNovaNasceComOsAnunciosSemLogin < ActiveRecord::Migration[7.2]
  FEATURE = 'anuncios_sem_login'.freeze

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

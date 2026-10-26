require Rails.root.join('lib/feature_flag_rollout')

# #2228 — conta nova nasce com a Fase 2 dos Agentes ligada. Esta migration liga só a parte que é flag: o
# agente_so_informa (#2166, o agente avisa e a Atribuição passa a conversa). As chaves de internal_attributes
# (autonomia_agents_fase2, autonomia_agente_ia_por_caixa) nascem pelo Autonomia::AccountProvisioningDefaults.
# Liga só o padrão das contas novas (ACCOUNT_LEVEL_FEATURE_DEFAULTS): as contas existentes não são tocadas. Mudar o
# features.yml não basta, porque o ConfigLoader do deploy roda com reconcile_only_new e preserva o `enabled` gravado.
# O como está em lib/feature_flag_rollout.rb.
class ContaNovaNasceComOAgenteSoInforma < ActiveRecord::Migration[7.2]
  FEATURE = 'agente_so_informa'.freeze

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

require Rails.root.join('lib/feature_flag_rollout')

# #2067 — conta nova nasce com "Ficar com a conversa ao enviar" (o ícone ao lado do Enviar e o "Devolver para <agente>"),
# que o Rodrigo decidiu em 22/10/2026 nascer ligado em todas as contas. Liga só o padrão das contas novas
# (ACCOUNT_LEVEL_FEATURE_DEFAULTS): as contas existentes são ligadas pela Orquestração depois do deploy e não são tocadas
# aqui. Mudar o features.yml não basta, porque o ConfigLoader do deploy roda com reconcile_only_new e preserva o `enabled`
# gravado. O como está em lib/feature_flag_rollout.rb (o mesmo caminho do #1977 e do #2045).
class ContaNovaNasceComFicarComAConversa < ActiveRecord::Migration[7.2]
  FEATURES = %w[ficar_com_a_conversa_ao_enviar].freeze

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

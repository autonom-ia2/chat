require Rails.root.join('lib/feature_flag_rollout')

# #1934 — conta nova nasce com a foto do contato no Híbrido (`hibrido_foto_do_contato`). Decisão do Rodrigo (20/10/2026):
# o Híbrido já está liberado e o gate é a própria caixa híbrida (WhatsappHybrid::FotoDoContato), então a flag segue
# quem já pode, em todas as contas. As existentes a Orquestração liga depois do deploy, com backup; esta migration liga
# só o padrão das contas novas (ACCOUNT_LEVEL_FEATURE_DEFAULTS). Mudar o features.yml não basta, porque o ConfigLoader do
# deploy roda com reconcile_only_new e preserva o `enabled` gravado. O como está em lib/feature_flag_rollout.rb (o mesmo
# caminho do #1927).
class ContaNovaNasceComAFotoDoContatoHibrido < ActiveRecord::Migration[7.2]
  FEATURES = %w[hibrido_foto_do_contato].freeze

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

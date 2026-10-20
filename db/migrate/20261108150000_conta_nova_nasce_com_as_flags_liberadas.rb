require Rails.root.join('lib/feature_flag_rollout')

# #1857 — conta nova nasce com as 14 funções que o Rodrigo liberou para todas as contas em 19/10/2026. Liga só o
# padrão das contas novas (ACCOUNT_LEVEL_FEATURE_DEFAULTS): as contas existentes já foram ligadas pela Orquestração e
# não são tocadas. Mudar o features.yml não basta, porque o ConfigLoader do deploy roda com reconcile_only_new e
# preserva o `enabled` gravado. O como está em lib/feature_flag_rollout.rb. Ficam de fora, por decisão do Rodrigo,
# `customer_base` e `instagram_assisted_onboarding` (esta segue com o padrão que já tem; a migration não a toca).
class ContaNovaNasceComAsFlagsLiberadas < ActiveRecord::Migration[7.2]
  FEATURES = %w[
    tela_inicial_resumo
    etiquetas_do_whatsapp
    whatsapp_hybrid_recovery
    horario_unico_caixa
    whatsapp_campaign_products
    followup_template_real_values
    crm_mensagem_marcada
    crm_avaliar_toda_mensagem
    crm_calendario_ouro
    crm_lembretes_v2
    conversa_cara_do_canal
    memoria_ia
    crm_outro_canal
    whatsapp_rich_native
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

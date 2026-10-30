require Rails.root.join('lib/feature_flag_rollout')

# #2221 — conta nova nasce com o contato na agenda do aparelho e a lida ao responder (#1865), que o Rodrigo mandou
# ligar em todas as contas (26/10/2026).
# Liga só o padrão das contas novas (ACCOUNT_LEVEL_FEATURE_DEFAULTS): as contas existentes são ligadas pela
# Orquestração e não são tocadas. Mudar o features.yml não basta, porque o ConfigLoader do deploy roda com
# reconcile_only_new e preserva o `enabled` gravado. O como está em lib/feature_flag_rollout.rb.
class ContaNovaNasceComAAgendaDoContato < ActiveRecord::Migration[7.2]
  FEATURE = 'whatsapp_agenda_do_contato'.freeze

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

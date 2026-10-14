require Rails.root.join('lib/feature_flag_rollout')

# #1335 — a conversa aberta na campanha (`campaign_open_window_text`) nasce ligada: liga o padrão de contas novas e liga
# em toda conta que ainda não tiver. O como está em lib/feature_flag_rollout.rb, o mesmo do #1398 e do #1399.
class EnableCampaignOpenWindowText < ActiveRecord::Migration[7.2]
  FEATURE = 'campaign_open_window_text'.freeze

  def up
    FeatureFlagRollout.padrao!(FEATURE, true)
    FeatureFlagRollout.ligar_em_todas!(FEATURE, log_tag: 'ligar_conversa_aberta')
    GlobalConfig.clear_cache
  end

  # Volta só o padrão das contas novas. As contas existentes seguem como estão; desligar em todas é o SQL do plano de
  # volta do PR (tira o bit 262144 de feature_flags_ext_1).
  def down
    FeatureFlagRollout.padrao!(FEATURE, false)
    GlobalConfig.clear_cache
  end
end

require Rails.root.join('lib/feature_flag_rollout')

# #1459 — a tela nova de "Nova conversa" (`nova_conversa_tela`) nasce ligada: liga o padrão de contas novas e liga em
# toda conta que ainda não tiver. O como está em lib/feature_flag_rollout.rb, o mesmo do #1398, do #1399 e do #1335.
class LigarNovaConversaTela < ActiveRecord::Migration[7.2]
  FEATURE = 'nova_conversa_tela'.freeze

  def up
    FeatureFlagRollout.padrao!(FEATURE, true)
    FeatureFlagRollout.ligar_em_todas!(FEATURE, log_tag: 'ligar_nova_conversa_tela')
    GlobalConfig.clear_cache
  end

  # Volta só o padrão das contas novas. As contas existentes seguem como estão; desligar em todas é o SQL do plano de
  # volta do PR (tira o bit 1048576, 1 << 20, de feature_flags_ext_1).
  def down
    FeatureFlagRollout.padrao!(FEATURE, false)
    GlobalConfig.clear_cache
  end
end

require Rails.root.join('lib/feature_flag_rollout')

# #1399 — o Agendamento WhatsApp-first (`crm_booking_v2`, #1187) deixa de ser piloto: liga o padrão de contas novas e
# liga em toda conta que ainda não tiver. O como está em lib/feature_flag_rollout.rb, o mesmo do #1398.
class LigarAgendamentoPorPadrao < ActiveRecord::Migration[7.2]
  FEATURE = 'crm_booking_v2'.freeze

  def up
    FeatureFlagRollout.padrao!(FEATURE, true)
    FeatureFlagRollout.ligar_em_todas!(FEATURE, log_tag: 'ligar_agendamento')
    GlobalConfig.clear_cache
  end

  # Volta só o padrão das contas novas. As contas existentes seguem como estão: desligar à força apagaria a escolha
  # de quem ligou depois. Voltar uma conta é pelo Super Admin ou pelo comando de rollback da #1399.
  def down
    FeatureFlagRollout.padrao!(FEATURE, false)
    GlobalConfig.clear_cache
  end
end

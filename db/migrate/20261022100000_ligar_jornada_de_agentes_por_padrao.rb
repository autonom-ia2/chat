require Rails.root.join('lib/feature_flag_rollout')

# #1181 — a jornada nova de Agentes (`autonomia_agents_journey`) passa a ser o padrão.
# Em 12/10/2026 o bit foi ligado em todas as contas ativas por psql (backup no comentário da #1181). Esta migration
# liga o padrão de contas novas e liga em toda conta que ainda não tiver (cobre conta criada entre o psql e o deploy).
# O como está em lib/feature_flag_rollout.rb, o mesmo do #1399 (crm_booking_v2).
class LigarJornadaDeAgentesPorPadrao < ActiveRecord::Migration[7.2]
  FEATURE = 'autonomia_agents_journey'.freeze

  def up
    FeatureFlagRollout.padrao!(FEATURE, true)
    FeatureFlagRollout.ligar_em_todas!(FEATURE, log_tag: 'ligar_jornada_de_agentes')
    GlobalConfig.clear_cache
  end

  # Volta só o padrão das contas novas. As contas existentes seguem como estão: voltar uma conta é restaurar o valor
  # dela do backup da #1181.
  def down
    FeatureFlagRollout.padrao!(FEATURE, false)
    GlobalConfig.clear_cache
  end
end

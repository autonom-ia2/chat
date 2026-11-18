require Rails.root.join('lib/feature_flag_rollout')

# #2902 (E9 do épico #1240) — as telas novas de Relacionamentos (`relacionamentos_novo`) viram o padrão: o código deixa
# de ler a flag no mesmo PR, e esta migration liga o padrão das contas novas e liga em toda conta que ainda não tem. O
# deploy roda a migration antes de servir o código novo. O como está em lib/feature_flag_rollout.rb, o mesmo do #1459.
#
# Backup: cada conta ligada vai ao log da migration com o valor de `feature_flags_ext_2` antes (só o id da conta e o
# número). As contas ligadas ficam também em InstallationConfig REGISTRO, para o `down` desligar SÓ elas: quem já tinha
# a flag antes (as contas piloto e as que a Orquestração ligou) continua com ela.
class LigarRelacionamentosNovoEmTodas < ActiveRecord::Migration[7.2]
  FEATURE = 'relacionamentos_novo'.freeze
  LOG_TAG = 'ligar_relacionamentos_novo'.freeze
  REGISTRO = 'ROLLOUT_RELACIONAMENTOS_NOVO_LIGADAS'.freeze

  def up
    FeatureFlagRollout.padrao!(FEATURE, true)
    ligadas = FeatureFlagRollout.ligar_em_todas!(FEATURE, log_tag: LOG_TAG)
    ligadas.each { |id, antes| say("backup conta=#{id} feature_flags_ext_2_antes=#{antes}") }
    say("contas ligadas agora: #{ligadas.size}")
    registrar(ligadas.keys)
    GlobalConfig.clear_cache
  end

  # Volta o padrão das contas novas e desliga a flag só nas contas que o `up` ligou. Sem o registro (já desfeito ou
  # apagado), nenhuma conta é desligada: o caminho é o backup do log.
  def down
    FeatureFlagRollout.padrao!(FEATURE, false)
    registro = InstallationConfig.find_by(name: REGISTRO)
    FeatureFlagRollout.desligar_nas_contas!(FEATURE, Array(registro&.value), log_tag: LOG_TAG)
    registro&.destroy!
    GlobalConfig.clear_cache
  end

  private

  # Rodar o `up` de novo soma as contas novas às que já estavam no registro, sem perder nenhuma.
  def registrar(ids)
    registro = InstallationConfig.find_or_initialize_by(name: REGISTRO)
    registro.value = (Array(registro.value) + ids).uniq
    registro.locked = true
    registro.save!
  end
end

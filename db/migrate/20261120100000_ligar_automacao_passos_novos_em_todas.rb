require Rails.root.join('lib/feature_flag_rollout')

# #2414 (Refs #2982) — os 6 passos novos da Automação livre (`automacao_passos_novos`) ficam ligados para todo mundo. O
# Rodrigo mandou ligar em todas em 13/11, e a Orquestração ligou nas contas que existiam. Faltava o padrão das contas
# novas: o `enabled: true` do features.yml não chega ao banco, porque o ConfigLoader do deploy roda com
# reconcile_only_new e mantém o `false` já gravado em ACCOUNT_LEVEL_FEATURE_DEFAULTS. Esta migration liga o padrão e
# liga em toda conta que ainda não tem (as criadas depois de 13/11). O como está em lib/feature_flag_rollout.rb, o
# mesmo da 20261118100000_ligar_relacionamentos_novo_em_todas.rb.
#
# Backup: cada conta ligada vai ao log da migration com o valor de `feature_flags_ext_2` antes (só o id da conta e o
# número). As contas ligadas ficam também em InstallationConfig REGISTRO, para o `down` desligar SÓ elas: quem já tinha
# a flag (as que a Orquestração ligou em 13/11) continua com ela.
class LigarAutomacaoPassosNovosEmTodas < ActiveRecord::Migration[7.2]
  FEATURE = 'automacao_passos_novos'.freeze
  LOG_TAG = 'ligar_automacao_passos_novos'.freeze
  REGISTRO = 'ROLLOUT_AUTOMACAO_PASSOS_NOVOS_LIGADAS'.freeze

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

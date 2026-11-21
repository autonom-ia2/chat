require Rails.root.join('lib/feature_flag_rollout')

# #3096 (F0 do épico #3095) — a porta da Automação (`automacao_porta`) fica ligada para todo mundo: a lista de
# Automações abre com a pergunta ao Guia e os 20 modelos do segmento da conta. A porta só aparece com o editor da
# Automação livre e com o Guia na conta (usePorta.js); sem o Guia, a tela continua a lista de hoje. Com a porta, o Guia
# monta automações no motor novo (Autonomia::Automacao.porta?), não mais em automation_rules.
#
# O `enabled: true` do features.yml não chega ao banco: o ConfigLoader do deploy roda com reconcile_only_new e mantém
# o `false` já gravado em ACCOUNT_LEVEL_FEATURE_DEFAULTS. Esta migration liga o padrão das contas novas e liga em toda
# conta que ainda não tem. O como está em lib/feature_flag_rollout.rb, o mesmo da
# 20261120100000_ligar_automacao_passos_novos_em_todas.rb.
#
# Backup: cada conta ligada vai ao log da migration com o valor de `feature_flags_ext_2` antes (só o id da conta e o
# número). As contas ligadas ficam também em InstallationConfig REGISTRO, para o `down` desligar SÓ elas: quem já tinha
# a flag continua com ela.
class LigarAutomacaoPortaEmTodas < ActiveRecord::Migration[7.2]
  FEATURE = 'automacao_porta'.freeze
  LOG_TAG = 'ligar_automacao_porta'.freeze
  REGISTRO = 'ROLLOUT_AUTOMACAO_PORTA_LIGADAS'.freeze

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

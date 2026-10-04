# Liga o aviso urgente do Guia (`guide_alert`, #935) no e-mail e no push dos administradores que já
# existiam (#944). O tipo novo nasce ligado só para quem entra numa conta depois do deploy
# (`AccountUser#create_notification_setting`); quem já estava ficava sem e-mail e sem push do aviso
# que existe justamente para não esperar.
#
# - Só administrador: é quem recebe aviso do Guia.
# - Só o bit do `guide_alert` (enum 11 → bit 2**(11-1) = 1024); os outros tipos ficam como a pessoa deixou.
# - Só a preferência que ninguém mexeu desde que a opção apareceu no perfil (merge do #938): quem salvou
#   depois já viu a opção e escolheu.
# - Idempotente (só toca quem ainda não tem o bit) e em lotes por id, sem transação longa.
#
# O `down` não desfaz: não há como saber quem já tinha ligado por conta própria.
class LigarAvisoDoGuiaParaAdministradores < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  GUIDE_ALERT_BIT = 1024
  ADMINISTRADOR = 1
  OPCAO_APARECEU_EM = '2026-10-04 04:29:38'.freeze
  LOTE = 1_000

  def up
    maior = select_value('SELECT MAX(id) FROM notification_settings').to_i
    (0..maior).step(LOTE) { |inicio| ligar(inicio, inicio + LOTE) }
  end

  def down; end

  private

  def ligar(inicio, fim)
    execute(<<~SQL.squish)
      UPDATE notification_settings ns
      SET email_flags = ns.email_flags | #{GUIDE_ALERT_BIT},
          push_flags = ns.push_flags | #{GUIDE_ALERT_BIT}
      FROM account_users au
      WHERE au.account_id = ns.account_id AND au.user_id = ns.user_id AND au.role = #{ADMINISTRADOR}
        AND ns.id >= #{inicio} AND ns.id < #{fim}
        AND ns.updated_at < '#{OPCAO_APARECEU_EM}'
        AND (ns.email_flags & #{GUIDE_ALERT_BIT} = 0 OR ns.push_flags & #{GUIDE_ALERT_BIT} = 0)
    SQL
  end
end

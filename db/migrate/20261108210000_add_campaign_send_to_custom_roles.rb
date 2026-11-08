# Disparar campanha saiu de `campaign_manage` para a chave nova `campaign_send` (#1898, épico #1784). Quem já
# disparava continua disparando: todo cargo com `campaign_manage` ganha `campaign_send`. Só dado; cargos criados
# depois nascem separados (quem só monta deixa a campanha pronta para outra pessoa disparar). O `down` tira a chave
# de todos os cargos, porque antes desta versão ela não existia; isso inclui quem a recebeu à mão depois do deploy,
# então um rollback pede conferir esses cargos.
class AddCampaignSendToCustomRoles < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL.squish
      UPDATE custom_roles
      SET permissions = array_append(permissions, 'campaign_send'), updated_at = NOW()
      WHERE 'campaign_manage' = ANY(permissions) AND NOT ('campaign_send' = ANY(permissions))
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE custom_roles
      SET permissions = array_remove(permissions, 'campaign_send'), updated_at = NOW()
      WHERE 'campaign_send' = ANY(permissions)
    SQL
  end
end

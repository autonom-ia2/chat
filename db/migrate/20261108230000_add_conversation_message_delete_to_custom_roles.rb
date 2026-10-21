# Apagar mensagem vira a chave própria `conversation_message_delete` (#1893, épico #1784). Quem já apagava continua
# apagando: todo cargo com alguma das três chaves de atender conversa ganha a chave nova. Quem só lê
# (`conversation_view`) já não apagava. Só dado; cargos criados depois nascem sem ela. O `down` tira a chave de todos os
# cargos, porque antes desta versão ela não existia; isso inclui quem a recebeu à mão depois do deploy, então um
# rollback pede conferir esses cargos.
class AddConversationMessageDeleteToCustomRoles < ActiveRecord::Migration[7.1]
  OPERATING_KEYS = %w[conversation_manage conversation_unassigned_manage conversation_participating_manage].freeze

  def up
    execute <<~SQL.squish
      UPDATE custom_roles
      SET permissions = array_append(permissions, 'conversation_message_delete'), updated_at = NOW()
      WHERE permissions && ARRAY[#{OPERATING_KEYS.map { |key| connection.quote(key) }.join(', ')}]::text[]
        AND NOT ('conversation_message_delete' = ANY(permissions))
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE custom_roles
      SET permissions = array_remove(permissions, 'conversation_message_delete'), updated_at = NOW()
      WHERE 'conversation_message_delete' = ANY(permissions)
    SQL
  end
end

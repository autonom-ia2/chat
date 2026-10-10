class AddWebhookToWhatsappHybridConnections < ActiveRecord::Migration[7.2]
  def up
    add_column :whatsapp_hybrid_connections, :public_id, :string
    add_column :whatsapp_hybrid_connections, :webhook_secret, :text
    add_column :whatsapp_hybrid_connections, :down_alerted_at, :datetime

    # Conexões já existentes (piloto) ganham link e segredo; o webhook é configurado na próxima consulta.
    select_values('SELECT id FROM whatsapp_hybrid_connections').each do |id|
      execute(sanitize(id))
    end

    change_column_null :whatsapp_hybrid_connections, :public_id, false
    add_index :whatsapp_hybrid_connections, :public_id, unique: true
  end

  def down
    remove_index :whatsapp_hybrid_connections, :public_id
    remove_column :whatsapp_hybrid_connections, :down_alerted_at
    remove_column :whatsapp_hybrid_connections, :webhook_secret
    remove_column :whatsapp_hybrid_connections, :public_id
  end

  private

  def sanitize(id)
    ActiveRecord::Base.sanitize_sql_array(
      ['UPDATE whatsapp_hybrid_connections SET public_id = ? WHERE id = ?', SecureRandom.uuid, id]
    )
  end
end

class CreateAutonomiaInsuranceConnections < ActiveRecord::Migration[7.2]
  def change # rubocop:disable Metrics/MethodLength
    create_table :autonomia_insurance_connections do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.string :provider, null: false, default: 'agger'
      # Estados do PRD §9.2 (not_configured, authenticating, discovering, ready, degraded, auth_required, offline)
      t.string :status, null: false, default: 'not_configured'
      # Credenciais da corretora no portal. Colunas text para caber o payload cifrado do
      # ActiveRecord::Encryption; o model recusa gravar sem cofre configurado.
      t.text :username
      t.text :password
      # O que pode ser exibido: login mascarado e nome da corretora no portal.
      t.string :username_hint
      t.string :external_account_label
      # Capability map normalizado devolvido pelo connector (produtos x seguradoras), sem segredos.
      t.jsonb :capabilities, null: false, default: {}
      t.string :capabilities_version
      t.string :last_error
      t.datetime :last_authenticated_at
      t.datetime :last_healthcheck_at
      t.datetime :last_capability_scan_at
      t.datetime :session_expires_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :autonomia_insurance_connections, [:account_id, :provider], unique: true,
                                                                          name: 'idx_autonomia_insurance_connections_account_provider'
  end
end

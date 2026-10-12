# Link curto da página de agendamento (#1282): `/a/<nome>` no lugar de `/book/<uuid>`. O nome é único na instalação
# inteira (a URL é global, não por conta) e fica gravado sempre em minúsculas (o modelo normaliza antes de validar),
# então o índice único simples já barra "Clinica" × "clinica". Página sem nome curto fica com NULL, que o índice
# único do Postgres não compara. Índice concorrente: não trava a escrita nas páginas enquanto é criado.
#
# Uma criação concorrente interrompida deixa o índice no banco marcado como inválido, e ele não garante unicidade.
# Rodar de novo o apaga e recria, em vez de pular por já existir um índice com o nome.
class AddShortNameToCrmAgentBookingProfiles < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  INDEX = 'index_crm_agent_booking_profiles_on_short_name'.freeze

  def up
    add_column :crm_agent_booking_profiles, :short_name, :string, if_not_exists: true
    remove_index :crm_agent_booking_profiles, name: INDEX, algorithm: :concurrently if invalid_index?
    add_index :crm_agent_booking_profiles, :short_name, unique: true, algorithm: :concurrently, if_not_exists: true, name: INDEX
  end

  def down
    remove_index :crm_agent_booking_profiles, name: INDEX, algorithm: :concurrently, if_exists: true
    remove_column :crm_agent_booking_profiles, :short_name, if_exists: true
  end

  private

  def invalid_index?
    select_value(<<~SQL.squish).present?
      SELECT 1 FROM pg_index JOIN pg_class ON pg_class.oid = pg_index.indexrelid
      WHERE pg_class.relname = #{connection.quote(INDEX)} AND NOT pg_index.indisvalid
    SQL
  end
end

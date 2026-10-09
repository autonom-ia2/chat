# Convidado sem e-mail (só WhatsApp/telefone), para reunião sem Google/Microsoft (#1188).
#
# Rollback: o `down` só volta o NOT NULL de `email` enquanto NÃO existir convidado com e-mail nulo.
# Depois que a página nova gravar convidados só com telefone, o caminho de volta é desligar a flag
# `crm_booking_v2` da conta, não reverter esta migration.
class RelaxCrmMeetingGuestsForPhoneOnlyGuests < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def up
    change_column_null :crm_meeting_guests, :email, true
    add_column :crm_meeting_guests, :phone_number, :string
    add_index :crm_meeting_guests, %i[account_id meeting_id phone_number],
              unique: true, where: 'phone_number IS NOT NULL',
              name: 'idx_crm_meeting_guests_unique_phone', algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :crm_meeting_guests, name: 'idx_crm_meeting_guests_unique_phone', algorithm: :concurrently, if_exists: true
    remove_column :crm_meeting_guests, :phone_number
    if select_value('SELECT 1 FROM crm_meeting_guests WHERE email IS NULL LIMIT 1')
      raise ActiveRecord::IrreversibleMigration, 'Existem convidados sem e-mail; desligue a flag crm_booking_v2 em vez de reverter.'
    end

    change_column_null :crm_meeting_guests, :email, false
  end
end

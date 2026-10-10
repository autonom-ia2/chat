# "Parar avisos" do cliente (#1192, J5-A7/J2-A9): uma linha por contato e conta. Vale para toda reunião do contato,
# inclusive as que ele marcar depois. Contato apagado leva a linha junto; a mescla de contatos move a linha.
class CreateCrmBookingNoticeStops < ActiveRecord::Migration[7.2]
  def change
    create_table :crm_booking_notice_stops do |t|
      t.bigint :account_id, null: false
      t.references :contact, null: false, foreign_key: { on_delete: :cascade }
      t.string :reason
      t.datetime :created_at, null: false
    end
    add_index :crm_booking_notice_stops, [:account_id, :contact_id], unique: true
  end
end

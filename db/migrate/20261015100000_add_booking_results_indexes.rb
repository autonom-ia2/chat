# Painel de resultados do agendamento (#1194, F2-C): os números do período contam eventos por data dentro da
# conta. Sem estes índices, "links enviados", "abriram" e "marcaram" varreriam todos os convites e reuniões da
# conta. Parciais (só linhas com o evento) e concorrentes, para não travar escrita em convites e reuniões.
class AddBookingResultsIndexes < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_index :crm_booking_invites, [:account_id, :sent_at], name: 'idx_crm_booking_invites_account_sent',
                                                             where: 'sent_at IS NOT NULL', algorithm: :concurrently, if_not_exists: true
    add_index :crm_booking_invites, [:account_id, :first_opened_at], name: 'idx_crm_booking_invites_account_opened',
                                                                     where: 'first_opened_at IS NOT NULL', algorithm: :concurrently,
                                                                     if_not_exists: true
    add_index :crm_meetings, [:account_id, :created_at], name: 'idx_crm_meetings_account_booked',
                                                         where: 'source IS NOT NULL', algorithm: :concurrently, if_not_exists: true
  end
end

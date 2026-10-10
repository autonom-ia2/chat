# Feriados nacionais (#1195, J3-A13): a página nova fecha nos feriados nacionais do Brasil, ligado por padrão, e o
# admin pode desligar. Tabela do fork; coluna com default constante não reescreve a tabela no Postgres 11+.
class AddCloseHolidaysToCrmAgentBookingProfiles < ActiveRecord::Migration[7.2]
  def change
    add_column :crm_agent_booking_profiles, :close_holidays, :boolean, default: true, null: false
  end
end

# Origem da reunião (conversa, link público, IA...) para reuniões sem provedor de calendário (#1188).
# Os enums `provider` (internal) e `online_meeting_type` (WhatsApp, link, presencial) ganham valores no modelo:
# são inteiros e não pedem migration.
class AddInternalBookingFieldsToCrmMeetings < ActiveRecord::Migration[7.2]
  def change
    add_column :crm_meetings, :source, :string
  end
end

# Índice da coluna de FK nova (#1193) antes do `on_delete`: apagar uma etapa não varre a tabela de páginas.
# Concorrente, para não travar escrita nas páginas.
class AddPostMeetingStageIndex < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_index :crm_agent_booking_profiles, :post_meeting_stage_id, algorithm: :concurrently, if_not_exists: true
  end
end

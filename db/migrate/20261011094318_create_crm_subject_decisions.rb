# Multifunil 5/11 (#1145): cada decisão da IA sobre o assunto de uma conversa, uma por mensagem.
# É o registro (custo, auditoria, "na dúvida avisa") e a sugestão do modo Sugerir (state = suggested).
# Apagar a conta, a conversa, o card ou o funil não esbarra aqui: a conta e a conversa levam as decisões junto.
class CreateCrmSubjectDecisions < ActiveRecord::Migration[7.2]
  def change
    create_table :crm_subject_decisions do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :message, foreign_key: { on_delete: :nullify }, index: false
      t.references :card, foreign_key: { to_table: :crm_cards, on_delete: :nullify }, index: false
      t.references :pipeline, foreign_key: { to_table: :crm_pipelines, on_delete: :nullify }, index: false
      t.string :action, null: false
      t.string :state, null: false
      t.string :mode, null: false
      t.string :title
      t.float :confidence
      t.string :decided_by
      t.string :reason
      t.timestamps
    end

    add_indexes
  end

  private

  def add_indexes
    add_index :crm_subject_decisions, %i[conversation_id message_id], unique: true, name: 'idx_crm_subject_decisions_message'
    add_index :crm_subject_decisions, %i[conversation_id state], name: 'idx_crm_subject_decisions_conversation_state'
    add_index :crm_subject_decisions, %i[account_id created_at], name: 'idx_crm_subject_decisions_account_month'
    add_index :crm_subject_decisions, :card_id
    add_index :crm_subject_decisions, :pipeline_id
    add_index :crm_subject_decisions, :message_id
  end
end

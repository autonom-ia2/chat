# #2277 — "Novo público pedindo em palavras": the person writes who they want, the account's own AI reads the
# conversations and builds the list to review. Three new tables, no change to existing ones:
# - conversation_audience_searches: one request, its plan (the rule the readers follow), progress and cost.
# - conversation_audience_batches: the conversations of the period split in batches for the readers, so a search
#   that stops (ceiling, AI error, the person) resumes where it was and a batch is never paid twice.
# - conversation_audience_people: who the readers found, one row per contact, with the group, the reason and the
#   timestamps of the messages that prove it. The saved audience itself is a regular campaign_imports audience.
class CreateConversationAudiences < ActiveRecord::Migration[7.2]
  def change
    create_searches
    create_batches
    create_people
  end

  private

  def create_searches # rubocop:disable Metrics/MethodLength -- one table, read top to bottom
    create_table :conversation_audience_searches do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, foreign_key: { on_delete: :nullify }
      t.text :request, null: false
      t.string :period, null: false
      t.text :answer
      t.jsonb :plan, null: false, default: {}
      t.string :status, null: false, default: 'planning'
      t.string :error
      t.integer :conversations_total, null: false, default: 0
      t.integer :conversations_read, null: false, default: 0
      t.decimal :estimate_usd, precision: 10, scale: 4
      t.decimal :ceiling_usd, precision: 10, scale: 4
      t.decimal :spent_usd, precision: 10, scale: 4, null: false, default: 0
      t.decimal :usd_brl, precision: 10, scale: 4
      t.references :campaign_import, foreign_key: { on_delete: :nullify }
      t.datetime :started_at
      t.datetime :finished_at
      t.datetime :heartbeat_at
      t.string :run_token
      t.timestamps
    end
    add_index :conversation_audience_searches, [:account_id, :status]
    add_index :conversation_audience_searches, [:account_id, :user_id, :created_at]
  end

  def create_batches
    create_table :conversation_audience_batches do |t|
      t.references :search, null: false, index: false,
                            foreign_key: { to_table: :conversation_audience_searches, on_delete: :cascade }
      t.integer :number, null: false
      t.bigint :conversation_ids, array: true, null: false, default: []
      t.integer :chars, null: false, default: 0
      t.string :status, null: false, default: 'pending'
      t.decimal :spent_usd, precision: 10, scale: 4, null: false, default: 0
      t.integer :attempts, null: false, default: 0
      t.string :error
      t.timestamps
    end
    add_index :conversation_audience_batches, [:search_id, :number], unique: true
    add_index :conversation_audience_batches, [:search_id, :status]
  end

  # conversation_id and contact_id indexed: deleting either cascades without a table scan. contact_masked and left_aside
  # are written when the person is found, so the screen polling the list never normalizes phones again.
  def create_people
    create_table :conversation_audience_people do |t|
      t.references :search, null: false, index: false,
                            foreign_key: { to_table: :conversation_audience_searches, on_delete: :cascade }
      t.references :contact, null: false, foreign_key: { on_delete: :cascade }
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }
      t.string :group, null: false
      t.text :reason
      t.jsonb :proofs, null: false, default: []
      t.string :contact_masked
      t.string :left_aside
      t.timestamps
    end
    add_index :conversation_audience_people, [:search_id, :contact_id], unique: true
  end
end

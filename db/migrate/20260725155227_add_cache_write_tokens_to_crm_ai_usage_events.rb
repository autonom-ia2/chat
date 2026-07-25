class AddCacheWriteTokensToCrmAiUsageEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_ai_usage_events, :cache_write_tokens, :integer, default: 0, null: false
  end
end

class AddAppScopedUserIdToChannelInstagram < ActiveRecord::Migration[7.2]
  def change
    # Meta deauthorize/data deletion callbacks identify the account by its app-scoped id (/me `id`),
    # not by the professional account id stored in instagram_id (/me `user_id`).
    add_column :channel_instagram, :app_scoped_user_id, :string
    add_index :channel_instagram, :app_scoped_user_id
  end
end

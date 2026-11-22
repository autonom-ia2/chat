class AddCallbackAuthToChannelSms < ActiveRecord::Migration[7.2]
  def up
    add_column :channel_sms, :secret, :string
    add_column :channel_sms, :callback_auth_enforced, :boolean, default: false, null: false
    # Fork (upgrade 4.20.1, #3120): a new inbox keeps callback_auth_enforced false, like the existing ones. Enforced by
    # default, the upstream check would answer 401 to the callback credentials of the fork guard (#1027); an admin can
    # turn it on in the inbox settings.

    Channel::Sms.reset_column_information
    Channel::Sms.where(secret: nil).find_each do |channel|
      channel.update_column(:secret, Channel::Sms.generate_unique_secure_token) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def down
    remove_column :channel_sms, :callback_auth_enforced
    remove_column :channel_sms, :secret
  end
end

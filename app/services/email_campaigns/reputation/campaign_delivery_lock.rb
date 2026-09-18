# Session advisory lock: competing SES workers do not share a campaign's rate budget.
# No transaction/row lock spans network I/O; process/connection loss releases ownership.
class EmailCampaigns::Reputation::CampaignDeliveryLock
  NAMESPACE = 436

  def self.synchronize(campaign_id)
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      owned = (Thread.current[:email_campaign_delivery_locks] ||= {})
      ownership = [connection.object_id, Integer(campaign_id)]
      return false if owned[ownership]

      # Hash the bigint id into the advisory namespace without truncating SQL identifiers.
      key = connection.quote("email_campaign_delivery:#{Integer(campaign_id)}")
      acquired = connection.select_value("SELECT pg_try_advisory_lock(#{NAMESPACE}, hashtext(#{key}))")
      return false unless acquired

      begin
        owned[ownership] = true
        yield
      ensure
        owned.delete(ownership)
        connection.select_value("SELECT pg_advisory_unlock(#{NAMESPACE}, hashtext(#{key}))")
      end
    end
  end
end

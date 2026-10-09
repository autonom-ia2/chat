class CustomExceptions::EmailReputationBlocked < StandardError
  attr_reader :protection

  def initialize(protection)
    @protection = protection
    super('email_campaign.protected')
  end
end

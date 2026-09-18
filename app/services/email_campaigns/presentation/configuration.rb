class EmailCampaigns::Presentation::Configuration
  def self.hygiene
    EmailCampaigns::HygieneConfig.new
  rescue ArgumentError
    # The public API never includes environment names or rejected values.
    raise CustomExceptions::EmailReputationConfiguration, 'hygiene_configuration_invalid'
  end
end

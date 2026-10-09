# Offline, no Rails, credentials, clients, database or network.
require 'minitest/autorun'

module CustomExceptions; end
require_relative '../../../../lib/custom_exceptions/email_reputation_configuration'

module EmailCampaigns; end
module EmailCampaigns::Reputation; end

module EmailCampaigns::Config
  def self.region
    'synthetic-region'
  end
end

require_relative '../../../../app/services/email_campaigns/reputation/provider_config'

class EmailProviderConfigTest < Minitest::Test
  def test_defaults_are_preventive_and_monitor_is_off
    config = EmailCampaigns::Reputation::ProviderConfig.new({})
    refute config.enabled
    refute config.manual_block
    assert_equal 0.05, config.bounce_ratio
    assert_equal 0.001, config.complaint_ratio
    assert_in_delta 0.04, config.bounce_recovery_ratio, 1e-12
    assert_in_delta 0.0008, config.complaint_recovery_ratio, 1e-12
    assert_equal 2, config.recovery_observations
  end

  def test_only_stricter_finite_positive_thresholds_are_accepted
    invalid_values = %w[0 -1 NaN Infinity invalid 0.10]
    %w[BOUNCE_RATIO COMPLAINT_RATIO].each do |key|
      invalid_values.each do |value|
        assert_raises(CustomExceptions::EmailReputationConfiguration) do
          EmailCampaigns::Reputation::ProviderConfig.new("EMAIL_REPUTATION_PROVIDER_#{key}" => value)
        end
      end
    end
    config = EmailCampaigns::Reputation::ProviderConfig.new('EMAIL_REPUTATION_PROVIDER_BOUNCE_RATIO' => '0.04',
                                                            'EMAIL_REPUTATION_PROVIDER_COMPLAINT_RATIO' => '0.0005')
    assert_equal 0.04, config.bounce_ratio
    assert_equal 0.0005, config.complaint_ratio
  end

  def test_recovery_thresholds_must_be_lower_than_blocking_thresholds
    assert_raises(CustomExceptions::EmailReputationConfiguration) do
      EmailCampaigns::Reputation::ProviderConfig.new('EMAIL_REPUTATION_PROVIDER_BOUNCE_RECOVERY_RATIO' => '0.05')
    end
    assert_raises(CustomExceptions::EmailReputationConfiguration) do
      EmailCampaigns::Reputation::ProviderConfig.new('EMAIL_REPUTATION_PROVIDER_COMPLAINT_RECOVERY_RATIO' => '0.001')
    end
    assert_raises(CustomExceptions::EmailReputationConfiguration) do
      EmailCampaigns::Reputation::ProviderConfig.new('EMAIL_REPUTATION_PROVIDER_RECOVERY_OBSERVATIONS' => '0')
    end
  end
end

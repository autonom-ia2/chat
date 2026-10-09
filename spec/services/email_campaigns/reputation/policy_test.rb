# Offline: ruby this_file.rb (no Rails, Bundler, environment loading or network).
require 'minitest/autorun'

module CustomExceptions; end
require_relative '../../../../lib/custom_exceptions/email_reputation_configuration'

module EmailCampaigns; end
module EmailCampaigns::Reputation; end

require_relative '../../../../app/services/email_campaigns/reputation/policy'
require_relative '../../../../app/services/email_campaigns/reputation/legacy_decision'

class EmailReputationPolicyTest < Minitest::Test
  def setup
    @policy = EmailCampaigns::Reputation::Policy.new({})
  end

  def test_permanent_classification_and_exact_boundaries
    assert_equal 'high_risk', @policy.evaluate(sent: 86, permanent: 4, transient: 1, complaints: 0)[:level]
    assert_equal false, @policy.evaluate(sent: 86, permanent: 4, transient: 1, complaints: 0)[:pause]
    assert_equal true, @policy.evaluate(sent: 100, permanent: 5, complaints: 0)[:pause]
    assert_equal false, @policy.evaluate(sent: 99, permanent: 4, complaints: 0)[:pause]
    assert_equal 'warning', @policy.evaluate(sent: 100, permanent: 2, complaints: 0)[:level]
    assert_equal 'high_risk', @policy.evaluate(sent: 100, permanent: 4, complaints: 0)[:level]
  end

  def test_complaint_thresholds_are_ratios_without_rounding
    assert_equal 'attention', @policy.evaluate(sent: 2000, permanent: 0, complaints: 1)[:level]
    assert_equal true, @policy.evaluate(sent: 1000, permanent: 0, complaints: 1)[:pause]
    assert_equal false, @policy.evaluate(sent: 1001, permanent: 0, complaints: 1)[:pause]
    assert_equal true, @policy.evaluate(sent: 100_000, permanent: 0, complaints: 1)[:spam_alert]
  end

  def test_hard_bounce_pause_requires_both_five_percent_and_five_outcomes
    assert_equal BigDecimal('0.05'), @policy.settings[:pause]
    assert_equal 5, @policy.settings[:min_permanent]
    refute @policy.evaluate(sent: 80, permanent: 4, complaints: 0)[:pause]
    refute @policy.evaluate(sent: 101, permanent: 5, complaints: 0)[:pause]
    assert @policy.evaluate(sent: 100, permanent: 5, complaints: 0)[:pause]
    prevented = @policy.evaluate(sent: 100, permanent: 0, provider_prevented: 5, complaints: 0)
    refute prevented[:pause]
    assert_equal 0.0, prevented[:permanent_ratio]
  end

  def test_tiny_and_zero_samples
    assert_equal false, @policy.evaluate(sent: 1, permanent: 1, complaints: 0)[:pause]
    assert_equal true, @policy.evaluate(sent: 1, permanent: 0, complaints: 1)[:pause]
    result = @policy.evaluate(sent: 0, permanent: 0, complaints: 0)
    assert_nil result[:permanent_ratio]
    assert_equal false, result[:resume_allowed]
  end

  def test_legacy_protection_cannot_be_released_by_the_new_policy
    metrics = { sent: 100, permanent: 0, transient: 6, bounced: 6, complaints: 0 }
    proposed = @policy.evaluate(metrics)[:resume_allowed]
    assert proposed
    assert EmailCampaigns::Reputation::LegacyDecision.pause?(metrics)
    refute EmailCampaigns::Reputation::LegacyDecision.resume_allowed?(metrics, proposed: proposed)
    refute EmailCampaigns::Reputation::LegacyDecision.resume_allowed?(metrics.merge(bounced: 0), proposed: false)
    assert EmailCampaigns::Reputation::LegacyDecision.resume_allowed?(metrics.merge(bounced: 0), proposed: true)
  end

  def test_invalid_configuration_fails_closed
    [
      { 'EMAIL_REPUTATION_MODE' => 'typo' },
      { 'EMAIL_REPUTATION_POLICY_VERSION' => 'v99' },
      { 'EMAIL_REPUTATION_PAUSE_RATIO' => 'NaN' },
      { 'EMAIL_REPUTATION_WARNING_RATIO' => '0.06' },
      { 'EMAIL_REPUTATION_MIN_PERMANENT' => '0' },
      { 'EMAIL_REPUTATION_PAUSE_RATIO' => 'garbage' }
    ].each { |config| assert_raises(ArgumentError) { EmailCampaigns::Reputation::Policy.new(config) } }
  end
end

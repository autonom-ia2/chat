# Offline only: no Rails boot, database, provider client or environment configuration.
ENV['MT_NO_PLUGINS'] = '1'
require 'minitest/autorun'
module EmailCampaigns; end
module EmailCampaigns::Reputation; end
require_relative '../../../app/services/email_campaigns/complaint_classifier'
require_relative '../../../app/services/email_campaigns/bounce_classifier'
require_relative '../../../app/services/email_campaigns/reputation/policy'
require_relative '../../../app/services/email_campaigns/reputation/legacy_decision'

class ComplaintReputationTest < Minitest::Test
  def test_only_account_and_tenant_suppression_are_prevention
    %w[OnAccountSuppressionList OnTenantSuppressionList].each do |subtype|
      complaint = { 'complaintSubType' => subtype }
      assert EmailCampaigns::ComplaintClassifier.provider_prevented?(complaint)
      refute EmailCampaigns::ComplaintClassifier.real_complaint?(complaint)
    end
  end

  def test_missing_null_unknown_and_bounce_only_subtypes_remain_real_complaints
    subtypes = %w[FutureUnknown Suppressed EmailValidationSuppressed UnsubscribedRecipient]
    complaints = [nil, {}, { 'complaintSubType' => nil }, { 'complaintSubType' => '' }]
    complaints.concat(subtypes.map { |subtype| { 'complaintSubType' => subtype } })
    complaints.each do |complaint|
      refute EmailCampaigns::ComplaintClassifier.provider_prevented?(complaint)
      assert EmailCampaigns::ComplaintClassifier.real_complaint?(complaint)
    end
  end

  def test_no_false_point_one_percent_pause_or_spam_alert
    complaints = %w[OnAccountSuppressionList OnTenantSuppressionList].map { |subtype| { 'complaintSubType' => subtype } }
    metrics = { sent: 1000, permanent: 0, bounced: 0,
                complaints: complaints.count { |details| EmailCampaigns::ComplaintClassifier.real_complaint?(details) } }
    result = EmailCampaigns::Reputation::Policy.new({}).evaluate(metrics)
    assert_equal 0.0, result[:complaint_ratio]
    refute result[:pause]
    refute result[:spam_alert]
    refute EmailCampaigns::Reputation::LegacyDecision.pause?(metrics.merge(sent: 100))
  end

  def test_real_complaint_still_pauses_at_point_one_percent
    result = EmailCampaigns::Reputation::Policy.new({}).evaluate(sent: 1000, permanent: 0, complaints: 1)
    assert_equal 0.001, result[:complaint_ratio]
    assert result[:pause]
    assert result[:spam_alert]
  end

  def test_global_suppressed_and_no_email_remain_permanent_bounces
    { 'Suppressed' => 'provider_suppression', 'NoEmail' => 'permanent_failure', 'General' => 'permanent_failure' }.each do |subtype, reason|
      assert_equal({ 'classification' => 'permanent', 'reason_code' => reason },
                   EmailCampaigns::BounceClassifier.call('bounceType' => 'Permanent', 'bounceSubType' => subtype))
    end
  end
end

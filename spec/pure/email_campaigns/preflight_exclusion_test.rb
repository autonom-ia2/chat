# Offline write-contract regression. Real SQL fencing/atomicity is tested by the parent Rails suite.
ENV['MT_NO_PLUGINS'] = '1'
require 'minitest/autorun'
require 'minitest/mock'
require 'active_support'
require 'active_support/core_ext'
module EmailCampaigns; end
ApplicationJob = Class.new do
  def self.queue_as(*); end
end
EmailCampaignRecipient = Class.new do
  def self.where(*); end
end
require_relative '../../../app/services/email_campaigns/hygiene_config'
require_relative '../../../app/jobs/email_campaigns/recipient_preflight_job'

class PreflightExclusionTest < Minitest::Test
  def setup
    @job = EmailCampaigns::RecipientPreflightJob.new
    @recipient = Struct.new(:id, :preflight_checked_at).new(1, nil)
    @scope = Minitest::Mock.new
    @lease = Object.new
    @writes = []
    @lease.define_singleton_method(:with_holder) do |token, &block|
      raise 'unexpected lease token' unless token == 'running-token'

      block.call
    end
    @scope.expect(:update_all, 1) { |attributes| @writes << attributes }
    @job.instance_variable_set(:@lease, @lease)
    @lookup = lambda do |**criteria|
      assert_equal({ id: 1, status: :pending, preflight_checked_at: nil }, criteria)
      @scope
    end
  end

  modes = %w[shadow warning enforce]
  statuses = %w[invalid review valid unknown unchecked]
  modes.product(statuses).each do |mode, status|
    define_method("test_#{mode}_#{status}_preserves_evidence_and_only_excludes_deterministic_enforce_findings") do
      config = EmailCampaigns::HygieneConfig.new('EMAIL_CAMPAIGN_HYGIENE_MODE' => mode)
      result = { status: status, reason_code: 'synthetic_reason', suggestion: 'person@example.org', valid_until: nil }
      EmailCampaignRecipient.stub(:where, @lookup) do
        @job.send(:persist_result, @recipient, result, 'running-token', config)
      end
      assert_equal 1, @writes.size
      attributes = @writes.first
      expected = { preflight_status: status, preflight_reason_code: result[:reason_code],
                   preflight_suggestion: result[:suggestion], preflight_valid_until: nil }
      expected[:status] = :suppressed if mode == 'enforce' && %w[invalid review].include?(status)
      assert_equal expected, attributes.except(:preflight_checked_at, :updated_at)
      assert_instance_of Time, attributes[:preflight_checked_at]
      assert_instance_of Time, attributes[:updated_at]
      @scope.verify
    end
  end
end

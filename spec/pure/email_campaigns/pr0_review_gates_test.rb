# Offline control-flow checks only. SQL/TTL semantics are covered by the focused Rails specs.
ENV['MT_NO_PLUGINS'] = '1'
require 'minitest/autorun'
require 'minitest/mock'
require 'active_support'
require 'active_support/core_ext'
module EmailCampaigns; end
module ActiveRecord; end
ActiveRecord::RecordInvalid = Class.new(StandardError)
ActiveRecord::ConnectionNotEstablished = Class.new(StandardError)
ApplicationJob = Class.new do
  def self.queue_as(*); end
end
EmailCampaign = Class.new do
  def self.where(*); end
end
EmailCampaignImport = Class.new do
  def self.active; end

  def self.where(*); end
end
EmailCampaignImport::RECOVERY_AFTER = 10.minutes
EmailCampaignImport::RETENTION = 1.day
EmailSuppression = Class.new do
  def self.blocking_reasons_for(*); end
end
EmailCampaigns::Config = Class.new do
  def self.enabled?
    true
  end
end
EmailCampaigns::RecipientPreflightJob = Class.new do
  def self.due; end

  def self.enqueue(*); end
end
Rails = Struct.new(:logger).new
require_relative '../../../app/jobs/email_campaigns/recipient_import_maintenance_job'
require_relative '../../../app/services/email_campaigns/preflight_decision'

class Pr0ReviewGatesTest < Minitest::Test
  # Query mechanics only: persisted eligibility is deliberately not simulated here.
  Scope = Struct.new(:rows) do
    def where(*) = self
    def not(*) = self
    def or(*) = self
    def select(*) = self
    def with_attached_source_file = self
    def find_each(**, &) = rows.each(&)
    def exists? = rows.any?
    def pluck(*) = rows

    def in_batches(of:)
      rows.each_slice(of) { |batch| yield self.class.new(batch) }
    end
  end
  Campaign = Struct.new(:id, :account, :import_active) do
    def recipient_import_active? = import_active
  end
  Config = Struct.new(:enforce) do
    def enforce? = enforce
  end

  def test_invalid_campaign_does_not_starve_other_campaigns_recovery_or_purge # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    campaigns = Scope.new([Campaign.new(1, nil, false), Campaign.new(2, nil, false)])
    logs = []
    Rails.logger = Object.new
    Rails.logger.define_singleton_method(:error) { |entry| logs << JSON.parse(entry) }
    purged = []
    file = Object.new
    file.define_singleton_method(:attached?) { true }
    file.define_singleton_method(:purge_later) { purged << 7 }
    expired = Struct.new(:source_file).new(file)
    job = EmailCampaigns::RecipientImportMaintenanceJob.new
    recovered = []
    visited = []
    enqueue = lambda do |id|
      raise ActiveRecord::RecordInvalid, 'must not expose private details' if id == 1

      visited << id
    end
    EmailCampaign.stub(:where, campaigns) do
      EmailCampaigns::RecipientPreflightJob.stub(:due, Scope.new([])) do
        EmailCampaigns::RecipientPreflightJob.stub(:enqueue, enqueue) do
          EmailCampaignImport.stub(:active, Scope.new([9])) do
            EmailCampaignImport.stub(:where, Scope.new([expired])) do
              job.stub(:recover, ->(id) { recovered << id }) { job.perform }
            end
          end
        end
      end
    end
    assert_equal [2], visited
    assert_equal [9], recovered
    assert_equal [7], purged
    assert_equal [{ 'event' => 'email_campaign_preflight_enqueue_failed', 'campaign_id' => 1,
                    'error_class' => 'ActiveRecord::RecordInvalid' }], logs
  end

  def test_global_failure_is_propagated_after_housekeeping_attempt
    job = EmailCampaigns::RecipientImportMaintenanceJob.new
    maintained = false
    failure = -> { raise ActiveRecord::ConnectionNotEstablished }
    job.stub(:enqueue_preflights, failure) do
      job.stub(:maintain_imports, -> { maintained = true }) do
        assert_raises(ActiveRecord::ConnectionNotEstablished) { job.perform }
      end
    end
    assert maintained
  end

  def test_blocked_pending_batches_use_authoritative_lookup_without_loading_whole_account
    account = Object.new
    campaign = Campaign.new(42, account, false)
    decision = EmailCampaigns::PreflightDecision.new(config: Config.new(true))
    emails = Array.new(1001) { |i| "person#{i}@example.org" }
    sizes = []
    lookup = lambda do |tenant, batch|
      assert_same account, tenant
      sizes << batch.size
      batch.index_with { |_email| 'unsubscribe' }
    end
    decision.stub(:unresolved, Scope.new(emails)) do
      EmailSuppression.stub(:blocking_reasons_for, lookup) { assert decision.campaign_allowed?(campaign) }
    end
    assert_equal [500, 500, 1], sizes
  end

  def test_eligible_unresolved_address_still_holds_campaign
    decision = EmailCampaigns::PreflightDecision.new(config: Config.new(true))
    decision.stub(:unresolved, Scope.new(['blocked@example.org', 'unknown@example.org'])) do
      EmailSuppression.stub(:blocking_reasons_for, { 'blocked@example.org' => 'unsubscribe' }) do
        refute decision.campaign_allowed?(Campaign.new(42, Object.new, false))
      end
    end
  end

  def test_active_import_is_never_allowed_in_shadow_or_enforce
    [false, true].each do |enforce|
      decision = EmailCampaigns::PreflightDecision.new(config: Config.new(enforce))
      refute decision.campaign_allowed?(Campaign.new(42, Object.new, true))
    end
  end
end

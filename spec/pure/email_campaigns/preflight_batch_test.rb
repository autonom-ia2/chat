# Offline batch execution: replace persistence only, execute the production cursor/budget loop.
ENV['MT_NO_PLUGINS'] = '1' # Never load installed Rails/minitest integration plugins.
require 'minitest/autorun'
require 'minitest/mock'
module EmailCampaigns; end
ApplicationJob = Class.new do
  def self.queue_as(*); end
end
Rails = Struct.new(:cache).new({})
require_relative '../../../app/services/email_campaigns/address_preflight'
require_relative '../../../app/services/email_campaigns/domain_validator'
module EmailCampaigns::Dns; end
require_relative '../../../app/services/email_campaigns/dns/mail_route_resolver'
require_relative '../../../app/jobs/email_campaigns/recipient_preflight_job'

class PreflightBatchTest < Minitest::Test
  Recipient = Struct.new(:id, :email)
  Scope = Struct.new(:rows) do
    def order(*)
      self
    end

    def limit(size)
      rows.first(size)
    end
  end
  Lease = Struct.new(:rows) do
    def remaining(cursor)
      Scope.new(rows.drop(cursor))
    end
  end
  Config = Struct.new(:enabled) do
    def dns_enabled?
      enabled
    end
  end

  def test_fifty_thousand_logical_recipients_advance_once_in_five_hundred_batches
    rows = Array.new(50_000) { |i| Recipient.new(i + 1, "person#{i}@example.org") }
    job = EmailCampaigns::RecipientPreflightJob.new
    job.instance_variable_set(:@lease, Lease.new(rows))
    visited = []
    cursor = 0
    writes = lambda { |recipient, result, _token, _config|
      visited << recipient.id
      assert_nil result[:valid_until]
    }
    job.stub(:persist_result, writes) do
      500.times do
        previous = cursor
        cursor = job.send(:process_batch, 'token', cursor, Config.new(false))
        assert_equal previous + 100, cursor
      end
    end
    assert_equal (1..50_000).to_a, visited
  end

  def test_slow_domains_yield_after_time_budget_with_monotonic_cursor_progress
    rows = Array.new(100) { |i| Recipient.new(i + 1, "person@domain#{i}.example.org") }
    job = EmailCampaigns::RecipientPreflightJob.new
    job.instance_variable_set(:@lease, Lease.new(rows))
    elapsed = 0
    lookup = lambda { |_domain|
      elapsed += 6
      { status: 'unknown', reason_code: 'dns_timeout', valid_until: Time.now.utc + 60 }
    }
    job.stub(:monotonic, -> { elapsed }) do
      job.stub(:persist_result, nil) do
        EmailCampaigns::DomainValidator.stub(:new, ->(*) { lookup }) do
          assert_equal 2, job.send(:process_batch, 'token', 0, Config.new(true))
          assert_equal 4, job.send(:process_batch, 'token', 2, Config.new(true))
        end
      end
    end
  end

  def test_fast_unique_domains_are_bounded_independently_of_time
    rows = Array.new(100) { |i| Recipient.new(i + 1, "person@domain#{i}.example.org") }
    job = EmailCampaigns::RecipientPreflightJob.new
    job.instance_variable_set(:@lease, Lease.new(rows))
    calls = 0
    lookup = lambda { |_domain|
      calls += 1
      { status: 'valid', reason_code: 'mx', valid_until: Time.now.utc + 60 }
    }
    job.stub(:persist_result, nil) do
      EmailCampaigns::DomainValidator.stub(:new, ->(*) { lookup }) do
        assert_equal 10, job.send(:process_batch, 'token', 0, Config.new(true))
      end
    end
    assert_equal 10, calls
  end

  def test_progresses_when_worker_was_stalled_before_reading_the_first_recipient
    job = EmailCampaigns::RecipientPreflightJob.new
    job.instance_variable_set(:@lease, Lease.new([Recipient.new(1, 'one@example.org'), Recipient.new(2, 'two@example.org')]))
    ticks = [0, 20]
    job.stub(:monotonic, -> { ticks.shift || 20 }) do
      job.stub(:persist_result, nil) do
        assert_equal 1, job.send(:process_batch, 'token', 0, Config.new(false))
      end
    end
  end
end

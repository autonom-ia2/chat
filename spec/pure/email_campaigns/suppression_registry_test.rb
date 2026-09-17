# Offline registry decisions only; real SQL, rollback and locks belong to the Rails specs.
ENV['MT_NO_PLUGINS'] = '1'
require 'minitest/autorun'
require 'minitest/mock'
require 'active_support'
require 'active_support/core_ext'
module EmailCampaigns; end
EmailSuppressionState = Class.new do
  def self.transaction
    yield
  end
end
require_relative '../../../app/services/email_campaigns/hygiene_config'
require_relative '../../../app/services/email_campaigns/suppression_registry'

class SuppressionRegistryTest < Minitest::Test
  Event = Struct.new(:id, :event_key, :action, :reason, :source, :occurred_at, :metadata, keyword_init: true)
  # Minimal in-memory query adapter, not a simulation of database concurrency.
  Events = Struct.new(:rows) do
    def where(attributes)
      self.class.new(rows.select { |row| attributes.all? { |key, value| value.is_a?(Range) ? value.cover?(row[key]) : row[key] == value } })
    end

    def find_by(event_key:) = rows.find { |row| row.event_key == event_key }
    def exists?(event_key:) = rows.any? { |row| event_key.include?(row.event_key) }
    def order(occurred_at:) = self.class.new(rows.sort_by(&:occurred_at).then { |sorted| occurred_at == :desc ? sorted.reverse : sorted })
    def limit(size) = self.class.new(rows.first(size))
    def pluck(key) = rows.map { |row| row[key] }
    def count = rows.size

    def create!(**attributes)
      event = Event.new(**attributes.slice(*Event.members), id: rows.size + 1)
      rows << event
      event
    end
  end
  State = Struct.new(:active, :reason, :source, :origin_campaign_id, :expires_at, :first_seen_at, :last_seen_at,
                     :occurrences, :email_suppression_events, keyword_init: true) do
    def assign_attributes(attributes)
      attributes.each { |key, value| self[key] = value }
    end

    def save! = true
  end

  def setup
    @now = Time.utc(2026, 9, 17, 12)
    @registry = EmailCampaigns::SuppressionRegistry.allocate
    @registry.instance_variable_set(:@config, EmailCampaigns::HygieneConfig.new({}))
    @state = State.new(active: false, occurrences: 0, email_suppression_events: Events.new([]))
    @mirrors = []
  end

  def with_registry(&)
    Time.stub(:current, @now) do
      @registry.stub(:locked_state, @state) do
        @registry.stub(:mirror_permanent!, ->(reason, source) { @mirrors << [reason, source] }, &)
      end
    end
  end

  def test_all_arrival_orders_use_the_newest_qualifying_event_and_deduplicate
    [@now, @now - 1.day, @now - 6.days].permutation.each do |times|
      @state = State.new(active: false, occurrences: 0, email_suppression_events: Events.new([]))
      with_registry do
        times.each_with_index do |time, index|
          2.times { @registry.record!(reason: 'temporary_failure', source: 'ses', event_key: time.iso8601, occurred_at: time) }
          assert_equal index == 2, @state.active
        end
      end
      assert_equal @now + 72.hours, @state.expires_at
      assert_equal 3, @state.occurrences
      assert_empty @mirrors
    end
  end

  def test_window_excludes_old_and_future_events_and_preserves_longer_expiry # rubocop:disable Metrics/AbcSize
    with_registry do
      [@now - 8.days, @now + 1.day, @now, @now - 1.day].each do |time|
        @registry.record!(reason: 'temporary_failure', source: 'ses', event_key: time.iso8601, occurred_at: time)
      end
      refute @state.active
      @registry.record!(reason: 'temporary_failure', source: 'ses', event_key: 'third', occurred_at: @now - 6.days)
      assert_equal @now + 72.hours, @state.expires_at
      @state.expires_at = @now + 5.days
      @registry.record!(reason: 'temporary_failure', source: 'ses', event_key: 'fourth', occurred_at: @now - 2.days)
      assert_equal @now + 5.days, @state.expires_at
    end
  end

  def test_same_key_promotes_once_without_rewriting_original_or_allowing_a_weaker_correction # rubocop:disable Metrics/AbcSize
    with_registry do
      original = @registry.record!(reason: 'unknown_bounce', source: 'ses', event_key: 'k' * 200, occurred_at: @now - 30.days).event
      snapshot = original.to_h.deep_dup
      promoted = @registry.block!(reason: 'hard_bounce', source: 'backfill', event_key: original.event_key)
      refute promoted.duplicate
      assert_equal 'correction', promoted.event.action
      assert_equal original.occurred_at, promoted.event.occurred_at
      assert_equal({ 'corrects_event_id' => original.id }, promoted.event.metadata)
      assert_operator promoted.event.event_key.length, :<=, 200
      %w[hard_bounce provider_suppression unknown_bounce temporary_failure].each do |reason|
        assert @registry.record!(reason: reason, source: 'backfill', event_key: original.event_key).duplicate
      end
      assert_equal snapshot, original.to_h
      assert_equal 2, @state.email_suppression_events.rows.size
      assert_equal 2, @state.occurrences
      assert_equal 'hard_bounce', @state.reason
      assert_nil @state.expires_at
      assert_equal [%w[hard_bounce backfill]], @mirrors
    end
  end

  def test_provider_to_hard_bounce_to_complaint_promotes_each_correction_once
    with_registry do
      @registry.block!(reason: 'provider_suppression', source: 'ses', event_key: 'durable')
      %w[hard_bounce complaint].each do |reason|
        refute @registry.block!(reason: reason, source: 'backfill', event_key: 'durable').duplicate
        assert @registry.block!(reason: reason, source: 'backfill', event_key: 'durable').duplicate
      end
      assert @registry.block!(reason: 'hard_bounce', source: 'backfill', event_key: 'durable').duplicate
      assert_equal 'complaint', @state.reason
      assert_equal 3, @state.email_suppression_events.rows.size
      assert_equal [%w[provider_suppression ses], %w[hard_bounce backfill], %w[complaint backfill]], @mirrors
    end
  end
end

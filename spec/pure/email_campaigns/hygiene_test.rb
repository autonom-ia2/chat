# Pure/offline contract checks; deliberately does not require rails_helper.
ENV['MT_NO_PLUGINS'] = '1' # Never load installed Rails/minitest integration plugins.
require 'minitest/autorun'
module EmailCampaigns; end
require_relative '../../../app/services/email_campaigns/hygiene_config'
require_relative '../../../app/services/email_campaigns/bounce_classifier'
require_relative '../../../app/services/email_campaigns/suppression_registry'
require_relative '../../../app/services/email_campaigns/domain_validator'
require_relative '../../../app/services/email_campaigns/address_preflight'

class EmailHygieneTest < Minitest::Test
  def test_configuration_is_opt_in_and_strict
    config = EmailCampaigns::HygieneConfig.new({})
    assert_equal 'shadow', config.mode
    refute config.dns_enabled?
    assert_equal 3, config.temporary_threshold
    assert_equal 7 * 86_400, config.temporary_window
    assert_equal 72 * 3600, config.quarantine_duration
    assert_raises(ArgumentError) { EmailCampaigns::HygieneConfig.new('EMAIL_CAMPAIGN_HYGIENE_MODE' => 'off') }
    assert_raises(ArgumentError) { EmailCampaigns::HygieneConfig.new('EMAIL_CAMPAIGN_SOFT_BOUNCE_THRESHOLD' => '0') }
    assert_raises(ArgumentError) { EmailCampaigns::HygieneConfig.new('EMAIL_CAMPAIGN_SOFT_BOUNCE_THRESHOLD' => '3x') }
  end

  def test_bounce_evidence_is_conservative
    classifier = EmailCampaigns::BounceClassifier
    assert_equal %w[permanent permanent_failure], classifier.call('bounceType' => 'Permanent', 'bounceSubType' => 'General').values
    assert_equal %w[permanent permanent_failure], classifier.call('bounceType' => 'Permanent', 'bounceSubType' => 'NoEmail').values
    assert_equal 'temporary', classifier.call('bounceType' => 'Transient')['classification']
    assert_equal 'unknown', classifier.call('bounceType' => 'Undetermined')['classification']
  end

  def test_provider_subtypes_distinguish_global_bounce_from_nonattempt_and_opt_out
    {
      'Suppressed' => %w[permanent provider_suppression],
      'OnAccountSuppressionList' => %w[unknown provider_suppression],
      'OnTenantSuppressionList' => %w[unknown provider_suppression],
      'EmailValidationSuppressed' => %w[unknown provider_suppression],
      'UnsubscribedRecipient' => %w[unknown unsubscribe]
    }.each do |subtype, expected|
      evidence = EmailCampaigns::BounceClassifier.call('bounceType' => 'Permanent', 'bounceSubType' => subtype)
      assert_equal expected, evidence.values, subtype
    end
  end

  # Table-driven offline protocol matrix; keep each case and its assertions together.
  def test_routes_and_inconclusive_dns # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    cases = [
      [{ MX: [:nxdomain, []] }, 'invalid', 'nxdomain'],
      [{ MX: [:timeout, []] }, 'unknown', 'dns_timeout'],
      [{ MX: [:servfail, []] }, 'unknown', 'dns_servfail'],
      [{ MX: [:refused, []] }, 'unknown', 'dns_refused'],
      [{ MX: [:ok, [[0, '.']]] }, 'invalid', 'null_mx'],
      [{ MX: [:ok, [[0, '.'], [10, 'mx.example.org']]] }, 'unknown', 'mixed_null_mx'],
      [{ MX: [:ok, [[10, 'mx.example.org']]] }, 'valid', 'mx'],
      [{ MX: [:ok, []], A: [:ok, ['192.0.2.1']] }, 'valid', 'implicit_mx'],
      [{ MX: [:ok, []], A: [:ok, []], AAAA: [:ok, ['2001:db8::1']] }, 'valid', 'implicit_mx'],
      [{ MX: [:ok, []], A: [:ok, []], AAAA: [:ok, []] }, 'invalid', 'no_mail_route'],
      [{ MX: [:ok, []], A: [:timeout, []], AAAA: [:ok, []] }, 'unknown', 'dns_timeout']
    ]
    cases.each do |answers, status, reason|
      queries = []
      resolver = lambda do |domain, type|
        queries << [domain, type]
        code, records = answers.fetch(type)
        { status: code, records: records, ttl: 60 }
      end
      cache = {}
      validator = EmailCampaigns::DomainValidator.new(resolver: resolver, cache: cache, clock: -> { Time.at(1000).utc })
      result = validator.call('EXAMPLE.ORG')
      assert_equal status, result[:status]
      assert_equal reason, result[:reason_code]
      assert_operator queries.size, :<=, 3
      count = queries.size
      assert_equal result, validator.call('example.org')
      assert_equal count, queries.size
      assert(cache.keys.none? { |key| key.include?('@') })
    end
  end

  def test_typo_review_never_repairs_identity_or_blacklists_business_domains
    validator = Object.new
    def validator.call(_domain)
      { status: 'valid', reason_code: 'mx', valid_until: Time.now.utc + 60 }
    end
    preflight = EmailCampaigns::AddressPreflight.new(validator: validator)
    { 'gmial.com' => 'gmail.com', 'gmail.con' => 'gmail.com', 'hotmial.com' => 'hotmail.com' }.each do |domain, suggestion|
      result = preflight.call("team+sales@#{domain}")
      assert_equal 'review', result[:status]
      assert_equal "team+sales@#{suggestion}", result[:suggestion]
    end
    assert_equal 'valid', preflight.call('sales@gmail-consulting.com')[:status]
    assert_equal 'valid', preflight.call('admin@example.org')[:status]
    assert_equal 'review', preflight.call('user@exämple.org')[:status]
    assert_equal 'invalid', preflight.call('usér@example.org')[:status]
  end

  def test_local_only_outcomes_do_not_expire
    preflight = EmailCampaigns::AddressPreflight.new
    %w[person@example.org person@gmial.com person@exämple.org].each do |address|
      assert_nil preflight.call(address)[:valid_until]
    end
  end

  def test_cache_expires
    now = Time.at(1000).utc
    count = 0
    resolver = lambda { |*|
      count += 1
      { status: :ok, records: [[10, 'mx.example.org']], ttl: 30 }
    }
    validator = EmailCampaigns::DomainValidator.new(resolver: resolver, cache: {}, clock: -> { now })
    validator.call('example.org')
    now += 31
    validator.call('example.org')
    assert_equal 2, count
  end
end

class EmailProviderSuppressionTest < Minitest::Test # rubocop:disable Style/OneClassPerFile -- isolated offline decision context
  # Model-shaped state only: persistence/transactions are covered by the parent's Rails suite.
  State = Struct.new(:active, :reason, :source, :origin_campaign_id, :expires_at, keyword_init: true) do
    def assign_attributes(attributes)
      attributes.each { |key, value| self[key] = value }
    end
  end

  def test_provider_prevention_promotes_temporary_state_to_nonexpiring_block
    registry = EmailCampaigns::SuppressionRegistry.allocate
    state = State.new(active: true, reason: 'temporary_failure', expires_at: Time.at(1000).utc)
    registry.send(:apply_block, state, 'provider_suppression', 'ses')
    assert state.active
    assert_equal 'provider_suppression', state.reason
    assert_equal 'ses', state.source
    assert_nil state.expires_at
    registry.send(:apply_block, state, 'temporary_failure', 'ses')
    assert_equal 'provider_suppression', state.reason
    assert_nil state.expires_at
  end

  def test_provider_block_is_strong_mirrored_and_cannot_downgrade_opt_out
    registry = EmailCampaigns::SuppressionRegistry.allocate
    state = State.new(active: true, reason: 'unsubscribe', source: 'link')
    mirrors = []
    write = ->(_attributes, &block) { block.call(state) }
    mirror = ->(reason, source) { mirrors << [reason, source] }
    registry.stub(:write, write) do
      registry.stub(:mirror_permanent!, mirror) do
        registry.block!(reason: 'provider_suppression', source: 'ses', event_key: 'provider:1', occurred_at: Time.at(500).utc)
      end
    end
    assert_equal [%w[provider_suppression ses]], mirrors
    assert state.active
    assert_equal 'unsubscribe', state.reason
    assert_equal 'link', state.source
    assert_nil state.expires_at
  end
end

require 'minitest/mock'
require 'timeout'
require 'socket'
module EmailCampaigns::Dns; end
require_relative '../../../app/services/email_campaigns/dns/mail_route_resolver'

class EmailHygieneResolverTest < Minitest::Test # rubocop:disable Style/OneClassPerFile -- separate offline test contexts
  def test_stdlib_does_not_confuse_nxdomain_with_no_data_or_timeout
    config_class = EmailCampaigns::Dns::MailRouteResolver::ObservedConfig
    {
      Resolv::DNS::Config::NXDomain => :nxdomain,
      Resolv::DNS::Config::OtherResolvError => :resolver_error,
      Resolv::ResolvTimeout => :timeout
    }.each do |exception, expected|
      config = config_class.new(nameserver: ['192.0.2.53'], search: [], ndots: 1)
      config.lazy_initialize
      config.timeouts = [1]
      # Exercise the real stdlib control flow without sending a packet.
      config.resolv('example.org.') { raise exception }
      assert_equal expected, config.failure
    end
  end

  def test_stdlib_record_extraction_without_network
    message = Resolv::DNS::Message.new
    name = Resolv::DNS::Name.create('example.org.')
    message.add_answer(name, 30, Resolv::DNS::Resource::IN::MX.new(0, Resolv::DNS::Name.create('.')))
    dns = Resolv::DNS.new(nameserver: ['192.0.2.53'], search: [], ndots: 1)
    fetch = ->(_domain, _type, &block) { block.call(message, name) }
    open = ->(&block) { block.call(dns) }
    dns.stub(:fetch_resource, fetch) do
      EmailCampaigns::Dns::MailRouteResolver::Resolver.stub(:open, open) do
        answer = EmailCampaigns::Dns::MailRouteResolver.new.call('example.org', :MX)
        assert_equal :ok, answer[:status]
        assert_equal [[0, '']], answer[:records]
        assert_equal 30, answer[:ttl]
      end
    end
  end
end

# Transport-level regression: real fetch_resource, TCP requester, framing and IO read.
# Only UDP exchange and TCP connection creation are replaced; no external packets.
class EmailHygieneDeadlineTest < Minitest::Test # rubocop:disable Style/OneClassPerFile -- transport regression context
  def test_truncated_udp_then_incomplete_tcp_frame_length_is_bounded_and_closed
    assert_truncated_timeout("\x00")
  end

  def test_truncated_udp_then_incomplete_tcp_frame_body_is_bounded_and_closed
    assert_truncated_timeout("\x00\x10x")
  end

  # Shared actual framing path; setup and ensure cleanup kept together to expose leaks.
  def assert_truncated_timeout(partial_frame) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    client, peer = Socket.pair(:UNIX, :STREAM, 0)
    peer.write(partial_frame) # readable but incomplete: blocks in real TCP#recv_reply
    truncated = Resolv::DNS::Message.new
    truncated.tc = 1
    udp = Minitest::Mock.new
    def udp.hash
      object_id.hash
    end
    udp.expect(:sender, :sender, [Object, Object, String, Integer])
    udp.expect(:request, [truncated, 'example.org.'], [:sender, Numeric])
    udp.expect(:close, nil)
    dns = EmailCampaigns::Dns::MailRouteResolver::Resolver.new
    resolver = EmailCampaigns::Dns::MailRouteResolver.new(timeout: 0.1)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    # Outer watchdog is test-only: before the fix it raises instead of returning UNKNOWN.
    Timeout.timeout(1) do
      dns.stub(:make_udp_requester, udp) do
        TCPSocket.stub(:new, client) do
          EmailCampaigns::Dns::MailRouteResolver::Resolver.stub(:open, ->(&block) { block.call(dns) }) do
            assert_equal :timeout, resolver.call('example.org', :MX)[:status]
          end
        end
      end
    end
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 0.8
    assert client.closed?
    udp.verify
  ensure
    client&.close unless client&.closed?
    peer&.close
    dns&.close
  end
end

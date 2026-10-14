require 'rails_helper'

RSpec.describe WhatsappProxy::ReconcileJob do
  let(:account) { create(:account) }
  let(:isp) { instance_double(Webshare::Client, configured?: true, proxies: []) }
  let(:datacenter) { instance_double(Webshare::Client, configured?: true, proxies: []) }
  let(:engine) { instance_double(Waha::Client) }
  # Status de cada sessão no motor (padrão WORKING) e sessões extras do motor sem atribuição.
  let(:statuses) { {} }
  let(:extra_sessions) { [] }
  let(:passwords) { {} }
  let(:engine_state) { {} }

  around do |example|
    with_modified_env(WHATSAPP_PROXY_ENABLED: 'true', WEBSHARE_ISP_PROXY_ADDRESSES: '10.5.0.1,10.5.0.2',
                      WEBSHARE_DATACENTER_PROXY_ADDRESSES: (1..10).flat_map { |i| ["10.0.0.#{i}", "10.1.0.#{i}"] }.join(',')) do
      example.run
    end
  end

  before do
    Redis::Alfred.delete(WhatsappProxy::Outage::PREVIOUS_KEY)
    %w[isp datacenter baseline].each { |scope| Redis::Alfred.delete(WhatsappProxy::Outage.episode_key(scope)) }
    %w[isp datacenter].each { |pool| Redis::Alfred.delete("whatsapp_proxy:plan_errors:#{pool}") }
    allow(Webshare::Client).to receive(:new).with(pool: 'isp').and_return(isp)
    allow(Webshare::Client).to receive(:new).with(pool: 'datacenter').and_return(datacenter)
    allow(Waha::Client).to receive(:new).and_return(engine)
    allow(engine).to receive(:list_sessions) { engine_view(statuses, engine: engine_state, passwords: passwords, extra: extra_sessions) }
  end

  def apply_jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job['job_class'] == 'WhatsappProxy::ApplyJob' }
  end

  def scheduled_sessions
    apply_jobs.map { |job| job['arguments'].first }
  end

  def scheduled_at(session)
    Time.zone.parse(apply_jobs.find { |job| job['arguments'].first == session }['scheduled_at'].to_s)
  end

  def waha!(name, owner = account, proxy:, digest: true, pool: 'datacenter')
    waha_session!(name, owner)
    assign_proxy!(name, proxy, account: owner, pool: pool, digest: (proxy.credential_digest if digest))
  end

  def clear_counters(*names)
    keys = %w[unstable_rounds drops unstable_swap gone_seen]
    names.product(keys).each { |name, key| Redis::Alfred.delete("whatsapp_proxy:#{key}:#{name}") }
  end

  it 'does nothing when every IP is still right' do
    proxy = webshare_proxy(id: 1, address: '10.0.0.1')
    waha!('5511900000001', proxy: proxy)
    allow(datacenter).to receive(:proxies).and_return([proxy, webshare_proxy(id: 2, address: '10.0.0.2')])

    expect { described_class.perform_now }.not_to have_enqueued_job(WhatsappProxy::ApplyJob)
  end

  describe 'vanished IP (M4)' do
    before do
      clear_counters('5511900000001')
      waha!('5511900000001', proxy: webshare_proxy(id: 1, address: '10.0.0.1'))
      allow(datacenter).to receive(:proxies).and_return([webshare_proxy(id: 2, address: '10.0.0.2')])
    end

    it 'swaps at once when the session is also off WORKING (urgent, no spacing)' do
      statuses['5511900000001'] = 'STARTING'

      described_class.perform_now

      expect(scheduled_sessions).to eq(['5511900000001'])
      expect(scheduled_at('5511900000001')).to be <= 5.seconds.from_now
      expect(WhatsappProxy::Assignment.last).to have_attributes(proxy_address: '10.0.0.2', previous_proxy_address: '10.0.0.1')
    end

    it 'waits for a second reading when the session is still WORKING, then swaps without urgency' do
      expect { described_class.perform_now }.not_to have_enqueued_job(WhatsappProxy::ApplyJob)

      described_class.perform_now

      expect(scheduled_sessions).to eq(['5511900000001'])
      expect(scheduled_at('5511900000001')).to be >= (described_class::SPACING - 5.seconds).from_now
    end

    it 'forgets the first reading when the IP comes back to the list' do
      described_class.perform_now
      allow(datacenter).to receive(:proxies).and_return([webshare_proxy(id: 1, address: '10.0.0.1')])
      described_class.perform_now
      allow(datacenter).to receive(:proxies).and_return([webshare_proxy(id: 2, address: '10.0.0.2')])

      expect { described_class.perform_now }.not_to have_enqueued_job(WhatsappProxy::ApplyJob)
    end
  end

  describe 'what is never touched (H2)' do
    it 'never touches a STOPPED session, even with its IP gone, and forgets how long it was off' do
      waha!('5511900000001', proxy: webshare_proxy(id: 1, address: '10.0.0.1'))
      Redis::Alfred.setex('whatsapp_proxy:off_since:5511900000001', 1.day.ago.to_i.to_s, 3600)
      statuses['5511900000001'] = 'STOPPED'
      allow(datacenter).to receive(:proxies).and_return([webshare_proxy(id: 2, address: '10.0.0.2')])

      2.times { described_class.perform_now }

      expect(apply_jobs).to be_empty
      expect(WhatsappProxy::Assignment.last.proxy_address).to eq('10.0.0.1')
      expect(Redis::Alfred.get('whatsapp_proxy:off_since:5511900000001')).to be_nil
    end

    it 'never reschedules a credential change while a change is in flight' do
      old = webshare_proxy(id: 1, address: '10.0.0.1', password: 'antiga')
      waha!('5511900000001', proxy: old)
      passwords['5511900000001'] = 'antiga'
      allow(datacenter).to receive(:proxies).and_return([webshare_proxy(id: 1, address: '10.0.0.1', password: 'nova')])
      WhatsappProxy::Assignment.last.update!(apply_scheduled_at: 5.minutes.ago)

      expect { described_class.perform_now }.not_to have_enqueued_job(WhatsappProxy::ApplyJob)
    end

    it 'reapplies a changed credential only while the session is WORKING' do
      old = webshare_proxy(id: 1, address: '10.0.0.1', password: 'antiga')
      waha!('5511900000001', proxy: old)
      passwords['5511900000001'] = 'antiga'
      allow(datacenter).to receive(:proxies).and_return([webshare_proxy(id: 1, address: '10.0.0.1', password: 'nova')])
      statuses['5511900000001'] = 'FAILED'

      expect { described_class.perform_now }.not_to have_enqueued_job(WhatsappProxy::ApplyJob)

      statuses['5511900000001'] = 'WORKING'
      expect { described_class.perform_now }.to have_enqueued_job(WhatsappProxy::ApplyJob).with('5511900000001')
    end

    it 'skips sessions in backoff without spending the slots of the round' do
      7.times do |i|
        owner = create(:account)
        name = "55119000000#{i}0"
        waha!(name, owner, proxy: webshare_proxy(id: i + 1, address: "10.0.0.#{i + 1}"))
        statuses[name] = 'STARTING'
      end
      WhatsappProxy::Assignment.order(:assigned_at).first(2).each { |row| row.update!(apply_failures: 1, last_apply_failed_at: Time.current) }
      allow(datacenter).to receive(:proxies).and_return((1..10).map { |i| webshare_proxy(id: i + 100, address: "10.1.0.#{i}") })

      described_class.perform_now

      expect(scheduled_sessions.size).to eq(described_class::MAX_CHANGES)
      expect(scheduled_sessions).not_to include(*WhatsappProxy::Assignment.where('apply_failures > 0').pluck(:session_name))
    end
  end

  describe 'pending assignment (M6)' do
    before do
      waha_session!('5511900000001', account)
      WhatsappProxy::Assignment.create!(session_name: '5511900000001', account_id: account.id, pool: 'datacenter', assigned_at: 1.hour.ago)
    end

    it 'waits while the session is not WORKING (L5)' do
      allow(datacenter).to receive(:proxies).and_return([webshare_proxy(id: 2, address: '10.0.0.2')])
      statuses['5511900000001'] = 'STARTING'

      expect { described_class.perform_now }.not_to have_enqueued_job(WhatsappProxy::ApplyJob)
      expect(WhatsappProxy::Assignment.last).to be_pending
    end

    it 'gets an IP and is scheduled once Webshare answers' do
      allow(datacenter).to receive(:proxies).and_return([webshare_proxy(id: 2, address: '10.0.0.2')])

      described_class.perform_now

      expect(scheduled_sessions).to eq(['5511900000001'])
      expect(WhatsappProxy::Assignment.last.proxy_address).to eq('10.0.0.2')
    end

    it 'counts a failure and waits (backoff) while there is still no IP' do
      described_class.perform_now
      expect(WhatsappProxy::Assignment.last).to have_attributes(pending?: true, apply_failures: 1)

      allow(datacenter).to receive(:proxies).and_return([webshare_proxy(id: 2, address: '10.0.0.2')])
      expect { described_class.perform_now }.not_to have_enqueued_job(WhatsappProxy::ApplyJob)

      travel_to(11.minutes.from_now) { described_class.perform_now }
      expect(scheduled_sessions).to eq(['5511900000001'])
    end
  end

  describe 'plan and account' do
    before { clear_counters('hybrid-5511900000001') }

    it 'leaves an imported number in the wrong plan alone unless WHATSAPP_PROXY_AUTO_MIGRATE is on' do
      hybrid_session!('hybrid-5511900000001', account)
      proxy = webshare_proxy(id: 1, address: '10.0.0.1')
      assign_proxy!('hybrid-5511900000001', proxy, account: account, digest: proxy.credential_digest).update!(origin: 'imported')
      allow(datacenter).to receive(:proxies).and_return([proxy])
      allow(isp).to receive(:proxies).and_return([webshare_proxy(id: 50, address: '10.5.0.1')])

      expect { described_class.perform_now }.not_to have_enqueued_job(WhatsappProxy::ApplyJob)

      with_modified_env(WHATSAPP_PROXY_AUTO_MIGRATE: 'true') do
        expect { described_class.perform_now }.to have_enqueued_job(WhatsappProxy::ApplyJob).with('hybrid-5511900000001')
      end
      expect(WhatsappProxy::Assignment.last).to have_attributes(pool: 'isp', proxy_address: '10.5.0.1')
    end

    it 'moves a number that changed type (WAHA → Hybrid) only while it is WORKING' do
      hybrid_session!('hybrid-5511900000001', account)
      proxy = webshare_proxy(id: 1, address: '10.0.0.1')
      assign_proxy!('hybrid-5511900000001', proxy, account: account, digest: proxy.credential_digest)
      allow(datacenter).to receive(:proxies).and_return([proxy])
      allow(isp).to receive(:proxies).and_return([webshare_proxy(id: 50, address: '10.5.0.1')])
      statuses['hybrid-5511900000001'] = 'FAILED'

      expect { described_class.perform_now }.not_to have_enqueued_job(WhatsappProxy::ApplyJob)

      statuses['hybrid-5511900000001'] = 'WORKING'
      expect { described_class.perform_now }.to have_enqueued_job(WhatsappProxy::ApplyJob).with('hybrid-5511900000001')
    end
  end

  describe 'convergence with the engine (the engine is the source of truth)' do
    let(:table_ip) { webshare_proxy(id: 1, address: '10.0.0.1') }
    let(:engine_ip) { webshare_proxy(id: 2, address: '10.0.0.2') }

    before do
      waha!('5511900000001', proxy: table_ip)
      allow(datacenter).to receive(:proxies).and_return([table_ip, engine_ip])
    end

    def engine_on(proxy, status: 'WORKING', password: nil, others: [])
      config = { 'proxy' => { 'server' => proxy.server, 'username' => "user-#{proxy.id}", 'password' => password || "senha-#{proxy.id}" } }
      allow(engine).to receive(:list_sessions).and_return([{ 'name' => '5511900000001', 'status' => status, 'config' => config }] + others)
    end

    def drift_scheduled?
      apply_jobs.map { |job| job['arguments'].first }.include?('5511900000001')
    end

    it 'adjusts the TABLE to the engine (no PUT) when the session is WORKING on a valid IP of its account and plan' do
      engine_on(engine_ip)

      expect { described_class.perform_now }.not_to have_enqueued_job(WhatsappProxy::ApplyJob)
      expect(WhatsappProxy::Assignment.last).to have_attributes(proxy_address: '10.0.0.2', credential_digest: engine_ip.credential_digest)
    end

    it 'schedules a normal change back to the table IP when the engine IP is not on the list anymore' do
      engine_on(webshare_proxy(id: 9, address: '10.0.0.9'))

      expect { described_class.perform_now }.to have_enqueued_job(WhatsappProxy::ApplyJob).with('5511900000001')
      expect(WhatsappProxy::Assignment.last.proxy_address).to eq('10.0.0.1')
    end

    it 'schedules a normal change when the engine IP belongs to another account' do
      other = create(:account)
      waha_session!('5511900000099', other)
      assign_proxy!('5511900000099', engine_ip, account: other)
      engine_on(engine_ip)

      expect { described_class.perform_now }.to have_enqueued_job(WhatsappProxy::ApplyJob).with('5511900000001')
      expect(WhatsappProxy::Assignment.find_by!(session_name: '5511900000001').proxy_address).to eq('10.0.0.1')
    end

    it 'reapplies when the engine has no proxy at all, respecting backoff' do
      allow(engine).to receive(:list_sessions).and_return([{ 'name' => '5511900000001', 'status' => 'WORKING', 'config' => {} }])

      expect { described_class.perform_now }.to have_enqueued_job(WhatsappProxy::ApplyJob).with('5511900000001')

      WhatsappProxy::Assignment.last.update!(apply_failures: 1, last_apply_failed_at: Time.current, apply_scheduled_at: nil)
      expect { described_class.perform_now }.not_to have_enqueued_job(WhatsappProxy::ApplyJob)
    end

    it 'waits while a change is in flight (scheduled minutes ago)' do
      engine_on(webshare_proxy(id: 9, address: '10.0.0.9'))
      WhatsappProxy::Assignment.last.update!(apply_scheduled_at: 5.minutes.ago)

      expect { described_class.perform_now }.not_to have_enqueued_job(WhatsappProxy::ApplyJob)
    end

    it 'never adopts an engine IP in quarantine: schedules the change back' do
      WhatsappProxy::Quarantine.put!('10.0.0.2', 'datacenter', 'teste')
      engine_on(engine_ip)

      described_class.perform_now

      expect(drift_scheduled?).to be(true)
      expect(WhatsappProxy::Assignment.last.proxy_address).to eq('10.0.0.1')
    end

    it 'never adopts when another session in the engine (unknown or of another account) uses the same IP' do
      engine_on(engine_ip, others: [{ 'name' => '5511900000077', 'status' => 'WORKING',
                                      'config' => { 'proxy' => { 'server' => '10.0.0.2:6000' } } }])

      described_class.perform_now

      expect(drift_scheduled?).to be(true)
      expect(WhatsappProxy::Assignment.find_by!(session_name: '5511900000001').proxy_address).to eq('10.0.0.1')
    end

    it 'never adopts above the per-IP limit (3 numbers of the account already on it)' do
      3.times { |i| waha!("551190000005#{i}", proxy: engine_ip) }
      engine_on(engine_ip, others: (0..2).map do |i|
        { 'name' => "551190000005#{i}", 'status' => 'WORKING',
          'config' => { 'proxy' => { 'server' => '10.0.0.2:6000', 'username' => 'user-2', 'password' => 'senha-2' } } }
      end)

      described_class.perform_now

      expect(drift_scheduled?).to be(true)
      expect(WhatsappProxy::Assignment.find_by!(session_name: '5511900000001').proxy_address).to eq('10.0.0.1')
    end

    it 'never adopts an IP that is reserved or outside the slice of the stack' do
      engine_on(engine_ip)

      with_modified_env(WEBSHARE_RESERVED_PROXY_ADDRESSES: '10.0.0.2') { described_class.perform_now }
      expect(drift_scheduled?).to be(true)

      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      WhatsappProxy::Assignment.last.update!(apply_scheduled_at: nil)
      with_modified_env(WEBSHARE_DATACENTER_PROXY_ADDRESSES: '10.0.0.1') { described_class.perform_now }
      expect(drift_scheduled?).to be(true)
    end

    it 'never adopts an IP of the other plan' do
      isp_ip = webshare_proxy(id: 50, address: '10.5.0.1')
      allow(isp).to receive(:proxies).and_return([isp_ip])
      engine_on(isp_ip)

      described_class.perform_now

      expect(drift_scheduled?).to be(true)
      expect(WhatsappProxy::Assignment.last.pool).to eq('datacenter')
    end

    it 'turns an imported assignment external when the engine moved to a proxy outside Webshare (alert once)' do
      WhatsappProxy::Assignment.last.update!(origin: 'imported')
      engine_on(webshare_proxy(id: 77, address: '200.1.1.1'))
      Redis::Alfred.delete('whatsapp_proxy:alert:proxy_manual_detectado:5511900000001')

      log = capture_log { 2.times { described_class.perform_now } }

      expect(apply_jobs).to be_empty
      expect(WhatsappProxy::Assignment.last).to have_attributes(external?: true, proxy_address: '200.1.1.1')
      expect(log.scan('[alerta] proxy_manual_detectado').size).to eq(1)
    end

    it 'does not adopt a valid IP while the session is off WORKING: urgent change back' do
      engine_on(engine_ip, status: 'FAILED')

      described_class.perform_now

      expect(drift_scheduled?).to be(true)
      expect(WhatsappProxy::Assignment.last.proxy_address).to eq('10.0.0.1')
    end

    it 'treats an in-flight change older than 30 min (worker stopped) as divergence' do
      engine_on(webshare_proxy(id: 9, address: '10.0.0.9'))
      WhatsappProxy::Assignment.last.update!(apply_scheduled_at: 31.minutes.ago)

      described_class.perform_now

      expect(drift_scheduled?).to be(true)
    end

    it 'skips a session whose proxy change is running (lock held)' do
      engine_on(webshare_proxy(id: 9, address: '10.0.0.9'))
      Redis::Alfred.set(WhatsappProxy::SessionLock.key('5511900000001'), 'job', nx: true, ex: 60)

      described_class.perform_now

      expect(drift_scheduled?).to be(false)
    ensure
      Redis::Alfred.delete(WhatsappProxy::SessionLock.key('5511900000001'))
    end

    it 'after a drift fails, waits for the backoff before trying again' do
      engine_on(webshare_proxy(id: 9, address: '10.0.0.9'))
      described_class.perform_now
      expect(drift_scheduled?).to be(true)
      WhatsappProxy::Assignment.last.apply_failed!

      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      described_class.perform_now

      expect(drift_scheduled?).to be(false)
    end

    it 'never rewrites nor reapplies when the engine masks the credential (contract), and alerts once' do
      Redis::Alfred.delete('whatsapp_proxy:alert:credencial_mascarada:5511900000001')
      Redis::Alfred.delete('whatsapp_proxy:masked_seen:5511900000001')
      WhatsappProxy::Assignment.last.update!(credential_digest: 'antigo')
      engine_on(table_ip, password: '********')

      log = capture_log { 2.times { described_class.perform_now } }

      expect(apply_jobs).to be_empty
      expect(WhatsappProxy::Assignment.last.credential_digest).to eq('antigo')
      expect(log.scan('[alerta] credencial_mascarada').size).to eq(1)
    end

    it 'records the credential the engine uses when the IP is the same' do
      engine_on(table_ip)
      WhatsappProxy::Assignment.last.update!(credential_digest: nil)

      described_class.perform_now

      expect(WhatsappProxy::Assignment.last.credential_digest).to eq(table_ip.credential_digest)
    end
  end

  it 'raises webshare_indisponivel for a plan with only pending numbers and a 401 in two rounds (MEDIUM a)' do
    hybrid_session!('hybrid-5511900000001', account)
    WhatsappProxy::Assignment.create!(session_name: 'hybrid-5511900000001', account_id: account.id, pool: 'isp', assigned_at: 1.hour.ago)
    allow(isp).to receive(:proxies).and_raise(Webshare::Client::Error, 'webshare_list_failed status=401')

    log = capture_log do
      described_class.perform_now
      travel_to(11.minutes.from_now) { described_class.perform_now }
    end

    expect(log).to include('[alerta] webshare_indisponivel')
  end

  it 'changes at most MAX_CHANGES sessions per run and warns when the whole list changed' do
    7.times do |i|
      owner = create(:account)
      name = "55119000000#{i}0"
      waha!(name, owner, proxy: webshare_proxy(id: i + 1, address: "10.0.0.#{i + 1}"))
      statuses[name] = 'STARTING'
    end
    allow(datacenter).to receive(:proxies).and_return((1..10).map { |i| webshare_proxy(id: i + 100, address: "10.1.0.#{i}") })

    log = capture_log { described_class.perform_now }

    expect(apply_jobs.size).to eq(described_class::MAX_CHANGES)
    expect(log).to include('troca_em_massa')
    expect(log).not_to include('senha-')
  end

  it 'skips sessions the engine does not have and deletes assignments without an inbox' do
    waha_session!('5511900000001', account)
    assign_proxy!('5511900000001', webshare_proxy(id: 1, address: '10.0.0.1'), account: account)
    assign_proxy!('5511900000077', webshare_proxy(id: 7, address: '10.0.0.7'), account: account)
    allow(engine).to receive(:list_sessions).and_return([])
    allow(datacenter).to receive(:proxies).and_return([webshare_proxy(id: 2, address: '10.0.0.2')])

    expect { described_class.perform_now }.not_to have_enqueued_job(WhatsappProxy::ApplyJob)
    expect(WhatsappProxy::Assignment.pluck(:session_name)).to eq(['5511900000001'])
  end

  it 'keeps one plan going when the other fails on Webshare, and alerts when it repeats (M2)' do
    hybrid_session!('hybrid-5511900000001', account)
    assign_proxy!('hybrid-5511900000001', webshare_proxy(id: 50, address: '10.5.0.9'), account: account, pool: 'isp')
    waha!('5511900000002', create(:account), proxy: webshare_proxy(id: 1, address: '10.0.0.1'))
    statuses.merge!('hybrid-5511900000001' => 'STARTING', '5511900000002' => 'STARTING')
    allow(isp).to receive(:proxies).and_raise(Webshare::Client::Error, 'webshare_list_failed status=429')
    allow(datacenter).to receive(:proxies).and_return([webshare_proxy(id: 2, address: '10.0.0.2')])

    log = capture_log { 2.times { described_class.perform_now } }

    expect(scheduled_sessions).to include('5511900000002')
    expect(scheduled_sessions).not_to include('hybrid-5511900000001')
    expect(log).to include('webshare_indisponivel')
    expect(WhatsappProxy::Outage.previous).to include('hybrid-5511900000001' => 'STARTING')
  end

  it 'counts a plan error once per round: one bad round never raises webshare_indisponivel (L2)' do
    hybrid_session!('hybrid-5511900000001', account)
    assign_proxy!('hybrid-5511900000001', webshare_proxy(id: 50, address: '10.5.0.9'), account: account, pool: 'isp')
    statuses['hybrid-5511900000001'] = 'STARTING'
    allow(isp).to receive(:proxies).and_raise(Webshare::Client::Error, 'webshare_list_failed status=401')

    log = capture_log { described_class.perform_now }

    expect(log).not_to include('webshare_indisponivel')
    expect(isp).to have_received(:proxies).once
  end

  it 'remembers the statuses of the round even when nothing is pending' do
    described_class.perform_now

    expect(WhatsappProxy::Outage.previous).to eq({})
  end

  it 'alerts and goes on when a new assignment is refused (L2)' do
    waha!('5511900000001', proxy: webshare_proxy(id: 1, address: '10.0.0.1'))
    waha!('5511900000002', create(:account), proxy: webshare_proxy(id: 3, address: '10.0.0.3'))
    statuses.merge!('5511900000001' => 'STARTING', '5511900000002' => 'STARTING')
    allow(datacenter).to receive(:proxies).and_return([webshare_proxy(id: 2, address: '10.0.0.2'), webshare_proxy(id: 4, address: '10.0.0.4')])
    allow_any_instance_of(WhatsappProxy::Assigner).to receive(:resolve).and_wrap_original do |original, name, *args| # rubocop:disable RSpec/AnyInstance
      raise ActiveRecord::RecordInvalid, WhatsappProxy::Assignment.new if name == '5511900000001'

      original.call(name, *args)
    end

    log = capture_log { described_class.perform_now }

    expect(log).to include('atribuicao_invalida')
    expect(scheduled_sessions).to eq(['5511900000002'])
  end

  it 'leaves hand-made external proxies alone' do
    waha_session!('5511900000001', account)
    WhatsappProxy::Assignment.create!(session_name: '5511900000001', account_id: account.id, pool: 'datacenter',
                                      proxy_address: '200.1.1.1', proxy_port: 3128, assigned_at: 1.day.ago)
    allow(datacenter).to receive(:proxies).and_return([webshare_proxy(id: 2, address: '10.0.0.2')])

    expect { described_class.perform_now }.not_to have_enqueued_job(WhatsappProxy::ApplyJob)
  end

  it 'does nothing while WHATSAPP_PROXY_ENABLED is off, even with the key' do
    waha!('5511900000001', proxy: webshare_proxy(id: 1, address: '10.0.0.1'))

    with_modified_env(WHATSAPP_PROXY_ENABLED: nil) do
      expect { described_class.perform_now }.not_to have_enqueued_job(WhatsappProxy::ApplyJob)
    end
    expect(datacenter).not_to have_received(:proxies)
  end
end

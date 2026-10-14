require 'rails_helper'

RSpec.describe WhatsappProxy::ReconcileJob do
  let(:account) { create(:account) }
  let(:isp) { instance_double(Webshare::Client, configured?: true, proxies: []) }
  let(:datacenter) { instance_double(Webshare::Client, configured?: true, proxies: []) }

  let(:engine) { instance_double(Waha::Client) }

  around do |example|
    with_modified_env(WHATSAPP_PROXY_ENABLED: 'true', WEBSHARE_ISP_PROXY_ADDRESSES: '10.5.0.1',
                      WEBSHARE_DATACENTER_PROXY_ADDRESSES: (1..10).flat_map { |i| ["10.0.0.#{i}", "10.1.0.#{i}"] }.join(',')) do
      example.run
    end
  end

  before do
    Redis::Alfred.delete(WhatsappProxy::Outage::PREVIOUS_KEY)
    %w[isp datacenter baseline].each { |scope| Redis::Alfred.delete(WhatsappProxy::Outage.episode_key(scope)) }
    allow(Webshare::Client).to receive(:new).with(pool: 'isp').and_return(isp)
    allow(Webshare::Client).to receive(:new).with(pool: 'datacenter').and_return(datacenter)
    allow(Waha::Client).to receive(:new).and_return(engine)
    # O motor tem todas as sessões atribuídas (sem proxy na listagem, para não pesar na escolha de IP livre).
    allow(engine).to receive(:list_sessions) { WhatsappProxy::Assignment.pluck(:session_name).map { |name| { 'name' => name } } }
  end

  def apply_jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job['job_class'] == 'WhatsappProxy::ApplyJob' }
  end

  it 'does nothing (no engine change scheduled) when every IP is still right' do
    proxy = webshare_proxy(id: 1, address: '10.0.0.1')
    waha_session!('5511900000001', account)
    assign_proxy!('5511900000001', proxy, account: account, digest: proxy.credential_digest)
    allow(datacenter).to receive(:proxies).and_return([proxy, webshare_proxy(id: 2, address: '10.0.0.2')])

    expect { described_class.perform_now }.not_to have_enqueued_job(WhatsappProxy::ApplyJob)
    expect(WhatsappProxy::Assignment.last.proxy_address).to eq('10.0.0.1')
  end

  it 'reassigns a session whose IP left the list and schedules the change in the engine' do
    waha_session!('5511900000001', account)
    assign_proxy!('5511900000001', webshare_proxy(id: 1, address: '10.0.0.1'), account: account)
    allow(datacenter).to receive(:proxies).and_return([webshare_proxy(id: 2, address: '10.0.0.2')])

    expect { described_class.perform_now }.to have_enqueued_job(WhatsappProxy::ApplyJob).with('5511900000001')
    expect(WhatsappProxy::Assignment.last.proxy_address).to eq('10.0.0.2')
  end

  it 'swaps a vanished IP at once, ahead of non-urgent changes, which stay spaced' do
    gone_account = create(:account)
    waha_session!('5511900000001', account)
    old = webshare_proxy(id: 1, address: '10.0.0.1', password: 'antiga')
    assign_proxy!('5511900000001', old, account: account, digest: old.credential_digest)
    waha_session!('5511900000002', gone_account)
    assign_proxy!('5511900000002', webshare_proxy(id: 9, address: '10.0.0.9'), account: gone_account)
    allow(datacenter).to receive(:proxies)
      .and_return([webshare_proxy(id: 1, address: '10.0.0.1', password: 'nova'), webshare_proxy(id: 2, address: '10.0.0.2')])

    described_class.perform_now

    at = apply_jobs.to_h { |job| [job['arguments'].first, Time.zone.parse(job['scheduled_at'].to_s)] }
    expect(at['5511900000002']).to be <= 5.seconds.from_now
    expect(at['5511900000001']).to be >= (described_class::SPACING - 5.seconds).from_now
  end

  it 'repairs a session already in STARTING whose IP vanished, but never one asking for a QR code' do
    other = create(:account)
    waha_session!('5511900000001', account)
    waha_session!('5511900000002', other)
    assign_proxy!('5511900000001', webshare_proxy(id: 1, address: '10.0.0.1'), account: account)
    assign_proxy!('5511900000002', webshare_proxy(id: 3, address: '10.0.0.3'), account: other)
    allow(engine).to receive(:list_sessions).and_return([{ 'name' => '5511900000001', 'status' => 'STARTING' },
                                                         { 'name' => '5511900000002', 'status' => 'SCAN_QR_CODE' }])
    allow(datacenter).to receive(:proxies).and_return([webshare_proxy(id: 2, address: '10.0.0.2'), webshare_proxy(id: 4, address: '10.0.0.4')])

    described_class.perform_now

    expect(apply_jobs.map { |job| job['arguments'].first }).to eq(['5511900000001'])
    expect(WhatsappProxy::Assignment.find_by!(session_name: '5511900000002').proxy_address).to eq('10.0.0.3')
  end

  it 'reapplies when Webshare changed the credential of the same IP' do
    waha_session!('5511900000001', account)
    old = webshare_proxy(id: 1, address: '10.0.0.1', password: 'antiga')
    assign_proxy!('5511900000001', old, account: account, digest: old.credential_digest)
    allow(datacenter).to receive(:proxies).and_return([webshare_proxy(id: 1, address: '10.0.0.1', password: 'nova')])

    expect { described_class.perform_now }.to have_enqueued_job(WhatsappProxy::ApplyJob).with('5511900000001')
    expect(WhatsappProxy::Assignment.last.proxy_address).to eq('10.0.0.1')
  end

  it 'leaves an imported number in the wrong plan alone unless WHATSAPP_PROXY_AUTO_MIGRATE is on' do
    hybrid_session!('hybrid-5511900000001', account)
    proxy = webshare_proxy(id: 1, address: '10.0.0.1')
    assign_proxy!('hybrid-5511900000001', proxy, account: account, pool: 'datacenter', digest: proxy.credential_digest)
      .update!(origin: 'imported')
    allow(datacenter).to receive(:proxies).and_return([proxy])
    allow(isp).to receive(:proxies).and_return([webshare_proxy(id: 50, address: '10.5.0.1')])

    expect { described_class.perform_now }.not_to have_enqueued_job(WhatsappProxy::ApplyJob)

    with_modified_env(WHATSAPP_PROXY_AUTO_MIGRATE: 'true') do
      expect { described_class.perform_now }.to have_enqueued_job(WhatsappProxy::ApplyJob).with('hybrid-5511900000001')
    end
  end

  it 'still fixes an imported number whose IP died' do
    waha_session!('5511900000001', account)
    assign_proxy!('5511900000001', webshare_proxy(id: 1, address: '10.0.0.1'), account: account).update!(origin: 'imported')
    allow(datacenter).to receive(:proxies).and_return([webshare_proxy(id: 2, address: '10.0.0.2')])

    expect { described_class.perform_now }.to have_enqueued_job(WhatsappProxy::ApplyJob).with('5511900000001')
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

  it 'moves a number that changed type (WAHA → Hybrid) to the right plan' do
    hybrid_session!('hybrid-5511900000001', account)
    proxy = webshare_proxy(id: 1, address: '10.0.0.1')
    assign_proxy!('hybrid-5511900000001', proxy, account: account, pool: 'datacenter', digest: proxy.credential_digest)
    allow(datacenter).to receive(:proxies).and_return([proxy])
    allow(isp).to receive(:proxies).and_return([webshare_proxy(id: 50, address: '10.5.0.1')])

    expect { described_class.perform_now }.to have_enqueued_job(WhatsappProxy::ApplyJob).with('hybrid-5511900000001')
    expect(WhatsappProxy::Assignment.last).to have_attributes(pool: 'isp', proxy_address: '10.5.0.1')
  end

  it 'changes at most MAX_CHANGES sessions per run, spaced, and warns when the whole list changed' do
    7.times do |i|
      account_i = create(:account)
      waha_session!("55119000000#{i}0", account_i)
      assign_proxy!("55119000000#{i}0", webshare_proxy(id: i + 1, address: "10.0.0.#{i + 1}"), account: account_i)
    end
    allow(datacenter).to receive(:proxies).and_return((1..10).map { |i| webshare_proxy(id: i + 100, address: "10.1.0.#{i}") })

    log = capture_log { described_class.perform_now }

    expect(apply_jobs.size).to eq(described_class::MAX_CHANGES)
    # IP sumido é urgente: todas já, sem espaçamento.
    expect(apply_jobs.map { |job| Time.zone.parse(job['scheduled_at'].to_s) }).to all(be <= 5.seconds.from_now)
    expect(WhatsappProxy::Assignment.where('proxy_address LIKE ?', '10.1.%').count).to eq(described_class::MAX_CHANGES)
    expect(log).to include('7 de 7 IPs atribuídos sumiram')
    expect(log).not_to include('senha-')
  end

  describe 'unstable session with an IP Webshare still calls valid' do
    let(:session) { '5511900000001' }
    let(:bad) { webshare_proxy(id: 1, address: '10.0.0.1') }
    let(:statuses) { { session => 'WORKING' } }

    before do
      %w[unstable_rounds drops unstable_swap scan_qr].each { |key| Redis::Alfred.delete("whatsapp_proxy:#{key}:#{session}") }
      %w[isp datacenter].each { |pool| Redis::Alfred.delete("whatsapp_proxy:outage:#{pool}") }
      waha_session!(session, account)
      assign_proxy!(session, bad, account: account, digest: bad.credential_digest)
      allow(datacenter).to receive(:proxies).and_return([bad, webshare_proxy(id: 2, address: '10.0.0.2')])
      allow(engine).to receive(:list_sessions) { statuses.map { |name, status| { 'name' => name, 'status' => status } } }
    end

    def round(status)
      statuses[session] = status
      described_class.perform_now
    end

    it 'swaps the IP after UNSTABLE_ROUNDS rounds off WORKING, and quarantines the bad IP' do
      expect { round('STARTING') }.not_to have_enqueued_job(WhatsappProxy::ApplyJob)

      log = capture_log { expect { round('FAILED') }.to have_enqueued_job(WhatsappProxy::ApplyJob).with(session) }

      expect(WhatsappProxy::Assignment.last.proxy_address).to eq('10.0.0.2')
      expect(WhatsappProxy::Quarantine.addresses).to eq(['10.0.0.1'])
      expect(log).to include('sessao_instavel_trocada', 'ip_em_quarentena')
    end

    it 'does nothing when the session is back to WORKING before UNSTABLE_ROUNDS' do
      round('STARTING')
      round('WORKING')

      expect { round('STARTING') }.not_to have_enqueued_job(WhatsappProxy::ApplyJob)
      expect(WhatsappProxy::Assignment.last.proxy_address).to eq('10.0.0.1')
    end

    it 'swaps on the fast signal: the Hybrid webhook saw the session drop MAX_DROPS times' do
      round('WORKING')
      WhatsappProxy::Health::MAX_DROPS.times { WhatsappProxy::Health.record_drop!(session) }

      expect { round('WORKING') }.to have_enqueued_job(WhatsappProxy::ApplyJob).with(session)
    end

    it 'only observes on the first round (no previous round known): no swap even with the counters already full' do
      WhatsappProxy::Health::MAX_DROPS.times { WhatsappProxy::Health.record_drop!(session) }

      expect { round('STARTING') }.not_to have_enqueued_job(WhatsappProxy::ApplyJob)
      expect(WhatsappProxy::Quarantine.count).to eq(0)
    end

    it 'only observes when Redis lost the previous round' do
      round('STARTING')
      Redis::Alfred.delete(WhatsappProxy::Outage::PREVIOUS_KEY)

      expect { round('STARTING') }.not_to have_enqueued_job(WhatsappProxy::ApplyJob)
    end

    it 'never swaps for SCAN_QR_CODE (unlinked device), only warns' do
      log = capture_log { 3.times { round('SCAN_QR_CODE') } }

      expect(apply_jobs).to be_empty
      expect(WhatsappProxy::Quarantine.count).to eq(0)
      expect(log.scan('aparelho_desvinculado').size).to eq(1)
    end

    it 'swaps at most once a day: still unstable afterwards only raises an alert' do
      round('STARTING')
      round('STARTING')
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      # O ApplyJob aplicou o IP novo.
      WhatsappProxy::Assignment.last.update!(credential_digest: webshare_proxy(id: 2, address: '10.0.0.2').credential_digest)

      log = capture_log { 2.times { round('STARTING') } }

      expect(apply_jobs).to be_empty
      expect(log).to include('sessao_instavel_de_novo')
    end

    it 'stops quarantining after DAILY_LIMIT IPs of the plan in 24 h, with an alert' do
      3.times { |i| WhatsappProxy::Quarantine.put!("10.9.0.#{i}", 'datacenter', 'antes') }

      log = capture_log { 2.times { round('STARTING') } }

      expect(apply_jobs).to be_empty
      expect(WhatsappProxy::Quarantine.addresses).not_to include('10.0.0.1')
      expect(log).to include('teto_de_quarentena')
    end

    it 'never hands a quarantined IP to anyone' do
      WhatsappProxy::Quarantine.put!('10.0.0.2', 'datacenter', 'teste')
      waha_session!('5511900000002', create(:account))
      statuses['5511900000002'] = 'WORKING'

      expect(WhatsappProxy::Assigner.new.for('5511900000002')).to be_nil
      expect(WhatsappProxy::Assignment.find_by(session_name: '5511900000002')).to be_nil
    end
  end

  describe 'general outage (Webshare, WhatsApp or the engine down) is not a bad IP' do
    let(:engine_sessions) { [] }

    before do
      allow(engine).to receive(:list_sessions) { engine_sessions }
      ips = (1..4).map { |i| webshare_proxy(id: i, address: "10.0.0.#{i}") }
      allow(datacenter).to receive(:proxies).and_return(ips + [webshare_proxy(id: 9, address: '10.0.0.9')])
      counters = %w[unstable_rounds drops unstable_swap]
      ips.each_with_index do |proxy, i|
        owner = create(:account)
        name = "551190000010#{i}"
        waha_session!(name, owner)
        assign_proxy!(name, proxy, account: owner, digest: proxy.credential_digest)
        counters.each { |key| Redis::Alfred.delete("whatsapp_proxy:#{key}:#{name}") }
      end
    end

    # proxied: status das 4 sessões com proxy nosso; unproxied: sem proxy; rotating: com proxy antigo sem atribuição.
    def round(proxied, unproxied: [], rotating: [])
      engine_sessions.replace(
        proxied.each_with_index.map { |status, i| { 'name' => "551190000010#{i}", 'status' => status } } +
        unproxied.each_with_index.map { |status, i| { 'name' => "55119000009#{i}", 'status' => status, 'config' => {} } } +
        rotating.each_with_index.map do |status, i|
          { 'name' => "55119000008#{i}", 'status' => status, 'config' => { 'proxy' => { 'server' => 'p.webshare.io:80' } } }
        end
      )
      described_class.perform_now
    end

    it 'does not quarantine nor swap when several IPs that were WORKING drop together, and alerts falha_geral' do
      round(%w[WORKING WORKING WORKING WORKING])

      log = capture_log do
        round(%w[STARTING STARTING FAILED WORKING])
        2.times { round(%w[STARTING STARTING FAILED WORKING]) }
      end

      expect(apply_jobs).to be_empty
      expect(WhatsappProxy::Quarantine.count).to eq(0)
      expect(log).to include('falha_geral')
      expect(WhatsappProxy::Outage.active?('datacenter')).to be(true)
    end

    it 'does not swap when the sessions without proxy (the baseline) that were WORKING drop too' do
      round(%w[WORKING WORKING WORKING WORKING], unproxied: %w[WORKING WORKING WORKING])
      2.times { round(%w[STARTING WORKING WORKING WORKING], unproxied: %w[FAILED STARTING WORKING]) }

      expect(apply_jobs).to be_empty
      expect(WhatsappProxy::Quarantine.count).to eq(0)
    end

    it 'never declares a general outage for sessions that were already off (old FAILED, old rotating proxy)' do
      round(%w[WORKING WORKING WORKING WORKING], unproxied: %w[FAILED FAILED], rotating: %w[FAILED FAILED FAILED])
      2.times { round(%w[STARTING WORKING WORKING WORKING], unproxied: %w[FAILED FAILED], rotating: %w[FAILED FAILED FAILED]) }

      expect(apply_jobs.map { |job| job['arguments'].first }).to eq(['5511900000100'])
      expect(WhatsappProxy::Outage.active?('datacenter')).to be(false)
    end

    it 'still repairs a vanished IP during a general outage (a Webshare fact, not a guess)' do
      round(%w[WORKING WORKING WORKING WORKING])
      allow(datacenter).to receive(:proxies).and_return((2..4).map { |i| webshare_proxy(id: i, address: "10.0.0.#{i}") } +
                                                         [webshare_proxy(id: 9, address: '10.0.0.9')])

      round(%w[STARTING STARTING FAILED WORKING])

      expect(apply_jobs.map { |job| job['arguments'].first }).to eq(['5511900000100'])
    end

    it 'ignores Hybrid webhook drops while a general outage is on' do
      Redis::Alfred.delete('whatsapp_proxy:drops:hybrid-x')
      Redis::Alfred.setex(WhatsappProxy::Outage.episode_key('baseline'), '["a","b"]', 60)
      WhatsappProxy::Health.record_drop!('hybrid-x')

      expect(WhatsappProxy::Health.drops('hybrid-x')).to eq(0)
    end
  end

  it 'leaves hand-made external proxies alone' do
    waha_session!('5511900000001', account)
    WhatsappProxy::Assignment.create!(session_name: '5511900000001', account_id: account.id, pool: 'datacenter',
                                      proxy_address: '200.1.1.1', proxy_port: 3128, assigned_at: 1.day.ago)

    expect { described_class.perform_now }.not_to have_enqueued_job(WhatsappProxy::ApplyJob)
  end

  it 'does nothing while WHATSAPP_PROXY_ENABLED is off, even with the key' do
    waha_session!('5511900000001', account)
    assign_proxy!('5511900000001', webshare_proxy(id: 1, address: '10.0.0.1'), account: account)

    with_modified_env(WHATSAPP_PROXY_ENABLED: nil) do
      expect { described_class.perform_now }.not_to have_enqueued_job(WhatsappProxy::ApplyJob)
    end
    expect(datacenter).not_to have_received(:proxies)
  end

  it 'does not call Webshare without the key' do
    allow(isp).to receive(:configured?).and_return(false)

    described_class.perform_now

    expect(datacenter).not_to have_received(:proxies)
  end
end

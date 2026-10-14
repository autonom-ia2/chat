require 'rails_helper'

# #1516: IP instável (quarentena e troca) e falha geral, com os caminhos tristes da revisão adversarial.
RSpec.describe WhatsappProxy::ReconcileJob do
  let(:account) { create(:account) }
  let(:isp) { instance_double(Webshare::Client, configured?: true, proxies: []) }
  let(:datacenter) { instance_double(Webshare::Client, configured?: true, proxies: []) }
  let(:engine) { instance_double(Waha::Client) }
  let(:statuses) { {} }
  let(:extra_sessions) { [] }

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
    allow(engine).to receive(:list_sessions) do
      WhatsappProxy::Assignment.pluck(:session_name).map { |name| { 'name' => name, 'status' => statuses.fetch(name, 'WORKING') } } +
        extra_sessions
    end
  end

  def scheduled_sessions
    ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job['job_class'] == 'WhatsappProxy::ApplyJob' }
                   .map { |job| job['arguments'].first }
  end

  def session!(name, proxy, owner: account)
    waha_session!(name, owner) unless WhatsappProxy::SessionOwner.find(name)
    assign_proxy!(name, proxy, account: owner, digest: proxy.credential_digest)
    %w[unstable_rounds drops unstable_swap gone_seen].each { |key| Redis::Alfred.delete("whatsapp_proxy:#{key}:#{name}") }
  end

  def round(changes = {})
    statuses.merge!(changes)
    described_class.perform_now
  end

  describe 'unstable session (H1, L1)' do
    let(:session) { '5511900000001' }
    let(:bad) { webshare_proxy(id: 1, address: '10.0.0.1') }

    before do
      session!(session, bad)
      allow(datacenter).to receive(:proxies).and_return([bad, webshare_proxy(id: 2, address: '10.0.0.2')])
    end

    it 'swaps the IP of a session that dropped from WORKING and stays off, and quarantines the bad IP' do
      round(session => 'WORKING')
      round(session => 'STARTING')

      log = capture_log { round(session => 'FAILED') }

      expect(scheduled_sessions).to eq([session])
      expect(WhatsappProxy::Assignment.last.proxy_address).to eq('10.0.0.2')
      expect(WhatsappProxy::Quarantine.addresses).to eq(['10.0.0.1'])
      expect(log).to include('sessao_instavel_trocada', 'ip_em_quarentena')
    end

    it 'never treats an old FAILED session (never WORKING) as unstable: no swap, no quarantine, no slot of the daily limit' do
      5.times { round(session => 'FAILED') }

      expect(scheduled_sessions).to be_empty
      expect(WhatsappProxy::Quarantine.count).to eq(0)
    end

    it 'starts over when the session is back to WORKING before UNSTABLE_ROUNDS' do
      round(session => 'WORKING')
      round(session => 'STARTING')
      round(session => 'WORKING')
      round(session => 'STARTING')

      expect(scheduled_sessions).to be_empty
    end

    it 'swaps on the fast signal (Hybrid webhook drops) once the previous round is known' do
      round(session => 'WORKING')
      with_modified_env(WHATSAPP_PROXY_ENABLED: 'true') do
        WhatsappProxy::Health::MAX_DROPS.times { WhatsappProxy::Health.record_drop!(session) }
      end

      round(session => 'WORKING')

      expect(scheduled_sessions).to eq([session])
    end

    it 'only observes on the first round (no previous round known)' do
      WhatsappProxy::Health::MAX_DROPS.times { WhatsappProxy::Health.record_drop!(session) }

      round(session => 'STARTING')

      expect(scheduled_sessions).to be_empty
    end

    it 'without a destination, never puts/removes a quarantine each round and alerts once a day (L1, L7)' do
      allow(datacenter).to receive(:proxies).and_return([bad])
      allow(WhatsappProxy::Quarantine).to receive(:put!).and_call_original
      Redis::Alfred.delete("whatsapp_proxy:alert:quarentena_sem_destino:#{session}:#{Date.current}")
      round(session => 'WORKING')
      round(session => 'STARTING')

      log = capture_log { 3.times { round(session => 'FAILED') } }

      expect(scheduled_sessions).to be_empty
      expect(WhatsappProxy::Quarantine).not_to have_received(:put!)
      expect(WhatsappProxy::Assignment.last.proxy_address).to eq('10.0.0.1')
      expect(log).to include('quarentena_sem_destino')
      expect(Redis::Alfred.ttl("whatsapp_proxy:alert:quarentena_sem_destino:#{session}:#{Date.current}")).to be > 1.hour.to_i
    end

    it 'undoes the provisional quarantine when the new assignment is refused (L3)' do
      round(session => 'WORKING')
      round(session => 'STARTING')
      allow_any_instance_of(WhatsappProxy::Assigner).to receive(:resolve) # rubocop:disable RSpec/AnyInstance
        .and_raise(ActiveRecord::RecordInvalid, WhatsappProxy::Assignment.new)

      log = capture_log { round(session => 'FAILED') }

      expect(WhatsappProxy::Quarantine.count).to eq(0)
      expect(scheduled_sessions).to be_empty
      expect(log).to include('atribuicao_invalida')
    end

    it 'swaps at most once a day' do
      round(session => 'WORKING')
      round(session => 'STARTING')
      round(session => 'FAILED')
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      WhatsappProxy::Assignment.last.update!(credential_digest: webshare_proxy(id: 2, address: '10.0.0.2').credential_digest)

      log = capture_log { [%w[WORKING], %w[STARTING], %w[FAILED]].each { |(status)| round(session => status) } }

      expect(scheduled_sessions).to be_empty
      expect(log).to include('sessao_instavel_de_novo')
      expect(Redis::Alfred.ttl("whatsapp_proxy:alert:sessao_instavel_de_novo:#{session}:#{Date.current}")).to be > 1.hour.to_i
    end

    it 'stops quarantining after DAILY_LIMIT IPs of the plan in 24 h' do
      3.times { |i| WhatsappProxy::Quarantine.put!("10.9.0.#{i}", 'datacenter', 'antes') }
      round(session => 'WORKING')
      round(session => 'STARTING')

      log = capture_log { round(session => 'FAILED') }

      expect(scheduled_sessions).to be_empty
      expect(log).to include('teto_de_quarentena')
    end
  end

  describe 'healthy sibling numbers on a quarantined IP (H1)' do
    let(:shared) { webshare_proxy(id: 1, address: '10.0.0.1') }

    before do
      %w[5511900000001 5511900000002 5511900000003].each { |name| session!(name, shared) }
      allow(datacenter).to receive(:proxies).and_return([shared] + (2..6).map { |i| webshare_proxy(id: i, address: "10.0.0.#{i}") })
    end

    it 'moves only the unstable one at once; WORKING siblings follow without urgency, one per round' do
      round('5511900000001' => 'WORKING')
      round('5511900000001' => 'STARTING')
      round('5511900000001' => 'FAILED')
      expect(scheduled_sessions).to eq(['5511900000001'])

      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      round

      expect(scheduled_sessions.size).to eq(1)
      expect(scheduled_sessions.first).to be_in(%w[5511900000002 5511900000003])
    end
  end

  describe 'a new outage never opens in the round the previous one ended (L6)' do
    before do
      (1..6).each { |i| session!("551190000020#{i}", webshare_proxy(id: i, address: "10.0.0.#{i}"), owner: create(:account)) }
      allow(datacenter).to receive(:proxies).and_return((1..9).map { |i| webshare_proxy(id: i, address: "10.0.0.#{i}") })
    end

    def six(*list)
      list.each_with_index.to_h { |status, i| ["551190000020#{i + 1}", status] }
    end

    it 'ends the old episode and only observes the new drops' do
      round(six('WORKING', 'WORKING', 'WORKING', 'WORKING', 'WORKING', 'WORKING'))
      round(six('STARTING', 'STARTING', 'WORKING', 'WORKING', 'WORKING', 'WORKING'))
      expect(WhatsappProxy::Outage.active?('datacenter')).to be(true)

      round(six('WORKING', 'WORKING', 'STARTING', 'STARTING', 'WORKING', 'WORKING'))

      expect(WhatsappProxy::Outage.active?('datacenter')).to be(false)
    end
  end

  describe 'aparelho desvinculado (L4)' do
    it 'never swaps for SCAN_QR_CODE and sends one summary the next day with the count' do
      session!('5511900000001', webshare_proxy(id: 1, address: '10.0.0.1'))
      session!('5511900000002', webshare_proxy(id: 3, address: '10.0.0.3'), owner: create(:account))
      allow(datacenter).to receive(:proxies).and_return([webshare_proxy(id: 2, address: '10.0.0.2')])
      day = Date.current
      [day, day - 1].each { |date| Redis::Alfred.delete("whatsapp_proxy:unlinked_count:#{date}") }
      %w[5511900000001 5511900000002].each { |name| Redis::Alfred.delete("whatsapp_proxy:unlinked:#{day}:#{name}") }
      Redis::Alfred.delete("whatsapp_proxy:unlinked_summary:#{day}")

      log = capture_log { 3.times { round('5511900000001' => 'SCAN_QR_CODE', '5511900000002' => 'SCAN_QR_CODE') } }
      expect(scheduled_sessions).to be_empty
      expect(log).not_to include('aparelho_desvinculado')

      next_day = capture_log { travel_to(1.day.from_now) { 2.times { round } } }
      expect(next_day.scan('[alerta] aparelho_desvinculado: 2 sessão').size).to eq(1)
    end
  end

  describe 'general outage (M1, L4)' do
    before do
      (1..4).each { |i| session!("551190000010#{i}", webshare_proxy(id: i, address: "10.0.0.#{i}"), owner: create(:account)) }
      allow(datacenter).to receive(:proxies).and_return((1..9).map { |i| webshare_proxy(id: i, address: "10.0.0.#{i}") })
    end

    def proxied(*list)
      list.each_with_index.to_h { |status, i| ["551190000010#{i + 1}", status] }
    end

    def baseline!(*list)
      extra_sessions.replace(list.each_with_index.map { |status, i| { 'name' => "55119000009#{i}", 'status' => status, 'config' => {} } })
    end

    it 'does not swap nor quarantine when several IPs that were WORKING drop together; alerts start and end once' do
      round(proxied('WORKING', 'WORKING', 'WORKING', 'WORKING'))

      log = capture_log do
        3.times { round(proxied('STARTING', 'STARTING', 'FAILED', 'WORKING')) }
        round(proxied('WORKING', 'WORKING', 'WORKING', 'WORKING'))
      end

      expect(scheduled_sessions).to be_empty
      expect(WhatsappProxy::Quarantine.count).to eq(0)
      expect(log.scan('[alerta] falha_geral:').size).to eq(1)
      expect(log.scan('[alerta] falha_geral_fim:').size).to eq(1)
    end

    it 'keeps a long outage as an outage: 3 of 4 IPs off for 2 hours → no quarantine, no change (HIGH1)' do
      start = Time.current
      travel_to(start) { round(proxied('WORKING', 'WORKING', 'WORKING', 'WORKING')) }
      log = capture_log do
        (1..12).each { |step| travel_to(start + (step * 10).minutes) { round(proxied('STARTING', 'STARTING', 'FAILED', 'WORKING')) } }
      end

      expect(scheduled_sessions).to be_empty
      expect(WhatsappProxy::Quarantine.count).to eq(0)
      expect(log.scan('[alerta] falha_geral:').size).to eq(1)
      episode_id = JSON.parse(Redis::Alfred.get(WhatsappProxy::Outage.episode_key('datacenter')))['id']
      expect(Redis::Alfred.ttl("whatsapp_proxy:alert:falha_geral:#{episode_id}")).to be > 1.hour.to_i
    end

    it 'ends when most came back; the one still off needs two NEW rounds off to be judged unstable (HIGH1)' do
      start = Time.current
      travel_to(start) { round(proxied('WORKING', 'WORKING', 'WORKING', 'WORKING')) }
      travel_to(start + 10.minutes) { round(proxied('STARTING', 'STARTING', 'FAILED', 'WORKING')) }
      travel_to(start + 20.minutes) { round(proxied('STARTING', 'WORKING', 'WORKING', 'WORKING')) }
      travel_to(start + 30.minutes) { round(proxied('STARTING', 'WORKING', 'WORKING', 'WORKING')) }
      expect(scheduled_sessions).to be_empty

      travel_to(start + 40.minutes) { round(proxied('STARTING', 'WORKING', 'WORKING', 'WORKING')) }

      expect(scheduled_sessions).to eq(['5511900000101'])
    end

    it 'treats the sessions without proxy as baseline only with at least MIN_BASELINE that were WORKING' do
      baseline!('WORKING', 'WORKING', 'WORKING')
      round(proxied('WORKING', 'WORKING', 'WORKING', 'WORKING'))
      baseline!('FAILED', 'STARTING', 'WORKING')
      round(proxied('STARTING', 'WORKING', 'WORKING', 'WORKING'))
      round(proxied('STARTING', 'WORKING', 'WORKING', 'WORKING'))

      expect(scheduled_sessions).to eq(['5511900000101'])
    end

    it 'does not swap when 5+ sessions without proxy that were WORKING drop too' do
      baseline!('WORKING', 'WORKING', 'WORKING', 'WORKING', 'WORKING')
      round(proxied('WORKING', 'WORKING', 'WORKING', 'WORKING'))
      baseline!('FAILED', 'STARTING', 'WORKING', 'WORKING', 'WORKING')
      2.times { round(proxied('STARTING', 'WORKING', 'WORKING', 'WORKING')) }

      expect(scheduled_sessions).to be_empty
    end

    it 'never declares an outage for sessions that were already off (old FAILED, old rotating proxy)' do
      extra_sessions.replace([{ 'name' => '551190000090', 'status' => 'FAILED', 'config' => {} },
                              { 'name' => '551190000091', 'status' => 'FAILED', 'config' => {} },
                              { 'name' => '551190000080', 'status' => 'FAILED', 'config' => { 'proxy' => { 'server' => 'p.webshare.io:80' } } }])
      round(proxied('WORKING', 'WORKING', 'WORKING', 'WORKING'))
      2.times { round(proxied('STARTING', 'WORKING', 'WORKING', 'WORKING')) }

      expect(scheduled_sessions).to eq(['5511900000101'])
      expect(WhatsappProxy::Outage.active?('datacenter')).to be(false)
    end

    it 'still repairs a vanished IP during a general outage' do
      round(proxied('WORKING', 'WORKING', 'WORKING', 'WORKING'))
      allow(datacenter).to receive(:proxies).and_return((2..9).map { |i| webshare_proxy(id: i, address: "10.0.0.#{i}") })

      round(proxied('STARTING', 'STARTING', 'FAILED', 'WORKING'))

      expect(scheduled_sessions).to eq(['5511900000101'])
    end

    it 'ignores Hybrid webhook drops while an outage is on, and when the feature is off (L3)' do
      Redis::Alfred.delete('whatsapp_proxy:drops:hybrid-x')
      with_modified_env(WHATSAPP_PROXY_ENABLED: nil) { WhatsappProxy::Health.record_drop!('hybrid-x') }
      Redis::Alfred.setex(WhatsappProxy::Outage.episode_key('baseline'), { id: 'baseline:1', members: %w[a b] }.to_json, 60)
      WhatsappProxy::Health.record_drop!('hybrid-x')

      expect(WhatsappProxy::Health.drops('hybrid-x')).to eq(0)
    end
  end
end

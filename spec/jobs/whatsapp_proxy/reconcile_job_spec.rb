require 'rails_helper'

RSpec.describe WhatsappProxy::ReconcileJob do
  let(:account) { create(:account) }
  let(:isp) { instance_double(Webshare::Client, configured?: true, proxies: []) }
  let(:datacenter) { instance_double(Webshare::Client, configured?: true, proxies: []) }

  around { |example| with_modified_env(WHATSAPP_PROXY_ENABLED: 'true') { example.run } }

  before do
    allow(Webshare::Client).to receive(:new).with(pool: 'isp').and_return(isp)
    allow(Webshare::Client).to receive(:new).with(pool: 'datacenter').and_return(datacenter)
    allow(Waha::Client).to receive(:new).and_return(instance_double(Waha::Client, list_sessions: []))
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

  it 'reapplies when Webshare changed the credential of the same IP' do
    waha_session!('5511900000001', account)
    old = webshare_proxy(id: 1, address: '10.0.0.1', password: 'antiga')
    assign_proxy!('5511900000001', old, account: account, digest: old.credential_digest)
    allow(datacenter).to receive(:proxies).and_return([webshare_proxy(id: 1, address: '10.0.0.1', password: 'nova')])

    expect { described_class.perform_now }.to have_enqueued_job(WhatsappProxy::ApplyJob).with('5511900000001')
    expect(WhatsappProxy::Assignment.last.proxy_address).to eq('10.0.0.1')
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
    expect(apply_jobs.map { |job| job['scheduled_at'] }.uniq.size).to eq(described_class::MAX_CHANGES)
    expect(WhatsappProxy::Assignment.where('proxy_address LIKE ?', '10.1.%').count).to eq(described_class::MAX_CHANGES)
    expect(log).to include('7 de 7 IPs atribuídos sumiram')
    expect(log).not_to include('senha-')
  end

  it 'leaves hand-made external proxies and sessions of no inbox here alone' do
    waha_session!('5511900000001', account)
    WhatsappProxy::Assignment.create!(session_name: '5511900000001', account_id: account.id, pool: 'datacenter',
                                      proxy_address: '200.1.1.1', proxy_port: 3128, assigned_at: 1.day.ago)
    assign_proxy!('5511900000077', webshare_proxy(id: 7, address: '10.0.0.7'), account: account)

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

require 'rails_helper'

RSpec.describe WhatsappProxy::ReconcileJob do
  let(:webshare) { instance_double(Webshare::Client, configured?: true) }

  before do
    allow(Webshare::Client).to receive(:new).and_return(webshare)
    Redis::Alfred.delete(WhatsappProxy::Assigner::BACKOFF_KEY)
  end

  def assign!(session, proxy)
    WhatsappProxy::Assignment.create!(session_name: session, webshare_proxy_id: proxy.id, proxy_address: proxy.address,
                                      proxy_port: proxy.port, assigned_at: 1.day.ago, credential_digest: proxy.credential_digest)
  end

  it 'does nothing when every assigned IP is still on the list with the same credential' do
    proxy = webshare_proxy(id: 1, address: '10.0.0.1')
    assign!('5511900000001', proxy)
    allow(webshare).to receive(:proxies).and_return([proxy, webshare_proxy(id: 2, address: '10.0.0.2')])

    expect { described_class.perform_now }.not_to have_enqueued_job(WhatsappProxy::ApplyJob)
    expect(WhatsappProxy::Assignment.last.proxy_address).to eq('10.0.0.1')
  end

  it 'reassigns a session whose IP left the list and schedules the change in the engine' do
    assign!('5511900000001', webshare_proxy(id: 1, address: '10.0.0.1'))
    allow(webshare).to receive(:proxies).and_return([webshare_proxy(id: 2, address: '10.0.0.2')])

    expect { described_class.perform_now }.to have_enqueued_job(WhatsappProxy::ApplyJob).with('5511900000001')
    expect(WhatsappProxy::Assignment.last.proxy_address).to eq('10.0.0.2')
  end

  it 'reapplies when Webshare changed the credential of the same IP' do
    assign!('5511900000001', webshare_proxy(id: 1, address: '10.0.0.1', password: 'antiga'))
    allow(webshare).to receive(:proxies).and_return([webshare_proxy(id: 1, address: '10.0.0.1', password: 'nova')])

    expect { described_class.perform_now }.to have_enqueued_job(WhatsappProxy::ApplyJob).with('5511900000001')
    expect(WhatsappProxy::Assignment.last.proxy_address).to eq('10.0.0.1')
  end

  it 'changes at most MAX_CHANGES sessions per run, spaced, and warns when the whole list changed' do
    7.times { |i| assign!("55119000000#{i}0", webshare_proxy(id: i + 1, address: "10.0.0.#{i + 1}")) }
    allow(webshare).to receive(:proxies).and_return((1..10).map { |i| webshare_proxy(id: i + 100, address: "10.1.0.#{i}") })

    log = capture_log { described_class.perform_now }

    jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job['job_class'] == 'WhatsappProxy::ApplyJob' }
    expect(jobs.size).to eq(described_class::MAX_CHANGES)
    expect(jobs.map { |job| job['scheduled_at'] }.uniq.size).to eq(described_class::MAX_CHANGES)
    expect(WhatsappProxy::Assignment.where('proxy_address LIKE ?', '10.1.%').count).to eq(described_class::MAX_CHANGES)
    expect(log).to include('7 de 7 IPs atribuídos sumiram')
    expect(log).not_to include('senha-')
  end

  it 'leaves hand-made external proxies alone' do
    WhatsappProxy::Assignment.create!(session_name: 'hybrid-5511900000001', proxy_address: '200.1.1.1', proxy_port: 3128,
                                      assigned_at: 1.day.ago)
    allow(webshare).to receive(:proxies).and_return([webshare_proxy(id: 2, address: '10.0.0.2')])

    expect { described_class.perform_now }.not_to have_enqueued_job(WhatsappProxy::ApplyJob)
  end

  it 'does not call Webshare without the key' do
    allow(webshare).to receive(:configured?).and_return(false)
    allow(webshare).to receive(:proxies)

    described_class.perform_now

    expect(webshare).not_to have_received(:proxies)
  end
end

require 'rails_helper'

RSpec.describe WhatsappProxy::Assigner do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:engine) { instance_double(Waha::Client, list_sessions: []) }
  let(:isp_list) { [] }
  let(:datacenter_list) { [] }
  let(:assigner) do
    described_class.new(engine: engine, pools: { isp: fake_pool('isp', isp_list), datacenter: fake_pool('datacenter', datacenter_list) })
  end
  let(:rio) { webshare_proxy(id: 1, address: '10.0.0.1', city: 'Rio de Janeiro') }
  let(:sao_paulo) { webshare_proxy(id: 2, address: '10.0.0.2', city: 'São Paulo') }
  let(:sao_paolo) { webshare_proxy(id: 3, address: '10.0.0.3', city: 'Sao Paolo') }
  let(:us) { webshare_proxy(id: 4, address: '10.0.0.4', country: 'US', city: 'New York') }
  let(:residential) { webshare_proxy(id: 50, address: '10.5.0.1') }

  around do |example|
    with_modified_env(WHATSAPP_PROXY_ENABLED: 'true', WEBSHARE_API_KEY: 'k',
                      WEBSHARE_ISP_PROXY_ADDRESSES: '10.5.0.1,10.6.0.1',
                      WEBSHARE_DATACENTER_PROXY_ADDRESSES: '10.0.0.1,10.0.0.2,10.0.0.3,10.0.0.4,10.0.0.5') { example.run }
  end

  before do
    %w[isp datacenter].each { |pool| Redis::Alfred.delete("whatsapp_proxy:backoff:#{pool}") }
  end

  describe 'session type chooses the plan' do
    let(:isp_list) { [residential] }
    let(:datacenter_list) { [sao_paulo] }

    it 'gives a Static Residential (isp) IP to a Hybrid session' do
      hybrid_session!('hybrid-5511900000001', account)

      expect(assigner.for('hybrid-5511900000001').address).to eq('10.5.0.1')
      expect(WhatsappProxy::Assignment.last).to have_attributes(pool: 'isp', account_id: account.id)
    end

    it 'gives a datacenter IP to a WAHA session' do
      waha_session!('5511900000001', account)

      expect(assigner.for('5511900000001').address).to eq('10.0.0.2')
      expect(WhatsappProxy::Assignment.last).to have_attributes(pool: 'datacenter', account_id: account.id)
    end

    it 'assigns nothing to a session without a known inbox' do
      expect(assigner.for('5511900000009')).to be_nil
    end
  end

  describe 'Brazil only' do
    let(:isp_list) { [webshare_proxy(id: 60, address: '10.6.0.1', country: 'US')] }
    let(:datacenter_list) { [us, rio] }

    it 'never falls back to another country' do
      hybrid_session!('hybrid-5511900000001', account)

      log = capture_log { expect(assigner.for('hybrid-5511900000001')).to be_nil }

      expect(log).to include('plano isp sem IP do Brasil livre')
    end

    it 'prefers São Paulo ("Sao Paolo" spelling too) among Brazilian IPs' do
      waha_session!('5511900000001', account)
      datacenter_list.push(sao_paolo)

      expect(assigner.for('5511900000001').address).to eq('10.0.0.3')
    end
  end

  describe 'one IP per account, up to N numbers' do
    let(:datacenter_list) { [sao_paulo, rio] }

    before { (1..4).each { |i| waha_session!("551190000000#{i}", account) } }

    it 'reuses the account IP until it holds N numbers, then takes a free one' do
      with_modified_env(WHATSAPP_PROXY_MAX_NUMBERS_PER_IP: '3') do
        addresses = (1..4).map { |i| assigner.for("551190000000#{i}").address }

        expect(addresses).to eq(%w[10.0.0.2 10.0.0.2 10.0.0.2 10.0.0.1])
      end
    end

    it 'never puts two accounts on the same IP' do
      waha_session!('5511900000099', other_account)
      assigner.for('5511900000001')

      expect(assigner.for('5511900000099').address).to eq('10.0.0.1')
    end

    it 'checks the per-IP limit only when the address changes (L1)' do
      assign_proxy!('5511900000001', sao_paulo, account: account)
      assign_proxy!('5511900000002', sao_paulo, account: account)

      with_modified_env(WHATSAPP_PROXY_MAX_NUMBERS_PER_IP: '1') do
        expect(WhatsappProxy::Assignment.find_by!(session_name: '5511900000001').update(apply_failures: 1)).to be(true)
      end
    end

    it 'refuses at the model level an IP of another account or above the limit' do
      assign_proxy!('5511900000001', sao_paulo, account: account)
      intruder = WhatsappProxy::Assignment.new(session_name: 'x', account_id: other_account.id, pool: 'datacenter',
                                               proxy_address: '10.0.0.2', proxy_port: 6000, assigned_at: Time.current)
      expect(intruder).not_to be_valid

      with_modified_env(WHATSAPP_PROXY_MAX_NUMBERS_PER_IP: '1') do
        same_account = intruder.tap { |record| record.account_id = account.id }
        expect(same_account).not_to be_valid
      end
    end

    it 'leaves the account without proxy rather than sharing with another account' do
      waha_session!('5511900000099', other_account)
      assign_proxy!('5511900000001', sao_paulo, account: account)
      assign_proxy!('5511900000002', rio, account: account)

      expect(assigner.for('5511900000099')).to be_nil
    end
  end

  describe 'type change' do
    let(:isp_list) { [residential] }
    let(:datacenter_list) { [sao_paulo] }

    before { hybrid_session!('hybrid-5511900000001', account) }

    it 'moves a number that became Hybrid from the datacenter IP to an isp IP' do
      assign_proxy!('hybrid-5511900000001', sao_paulo, account: account, pool: 'datacenter')

      expect(assigner.for('hybrid-5511900000001').address).to eq('10.5.0.1')
      expect(WhatsappProxy::Assignment.last).to have_attributes(pool: 'isp', origin: 'assigned')
    end

    it 'keeps an imported number where it is unless WHATSAPP_PROXY_AUTO_MIGRATE is on' do
      assign_proxy!('hybrid-5511900000001', sao_paulo, account: account, pool: 'datacenter').update!(origin: 'imported')

      expect(assigner.for('hybrid-5511900000001').address).to eq('10.0.0.2')
      with_modified_env(WHATSAPP_PROXY_AUTO_MIGRATE: 'true') do
        expect(assigner.for('hybrid-5511900000001').address).to eq('10.5.0.1')
      end
    end

    it 'moves an imported number whose IP died, straight to the right plan' do
      assign_proxy!('hybrid-5511900000001', webshare_proxy(id: 9, address: '10.0.0.9'), account: account, pool: 'datacenter')
        .update!(origin: 'imported')

      expect(assigner.for('hybrid-5511900000001').address).to eq('10.5.0.1')
    end
  end

  describe 'stack slice' do
    let(:datacenter_list) { [sao_paulo, rio, sao_paolo] }

    it 'offers no IP at all when the slice is empty, with an error log' do
      waha_session!('5511900000001', account)

      log = capture_log do
        with_modified_env(WEBSHARE_DATACENTER_PROXY_ADDRESSES: '') { expect(assigner.for('5511900000001')).to be_nil }
      end

      expect(log).to include('WEBSHARE_DATACENTER_PROXY_ADDRESSES vazia')
    end

    it 'never offers an IP reserved for another integration (e.g. Instagram), even inside the slice' do
      waha_session!('5511900000001', account)

      with_modified_env(WEBSHARE_DATACENTER_PROXY_ADDRESSES: '10.0.0.2,10.0.0.1', WEBSHARE_RESERVED_PROXY_ADDRESSES: '10.0.0.2') do
        expect(assigner.for('5511900000001').address).to eq('10.0.0.1')
      end
    end

    it 'leaves the number without proxy when the only IP left is reserved' do
      waha_session!('5511900000001', account)

      with_modified_env(WEBSHARE_DATACENTER_PROXY_ADDRESSES: '10.0.0.2', WEBSHARE_RESERVED_PROXY_ADDRESSES: ' 10.0.0.2 ') do
        expect(assigner.for('5511900000001')).to be_nil
      end
    end

    it 'only picks IPs of this stack slice' do
      waha_session!('5511900000001', account)

      with_modified_env(WEBSHARE_DATACENTER_PROXY_ADDRESSES: '10.0.0.1, 10.0.0.9') do
        expect(assigner.for('5511900000001').address).to eq('10.0.0.1')
      end
    end

    it 'warns loudly when a slice IP left the plan, and never leaves the slice' do
      waha_session!('5511900000001', account)
      assign_proxy!('5511900000050', rio, account: other_account)

      log = capture_log do
        with_modified_env(WEBSHARE_DATACENTER_PROXY_ADDRESSES: '10.0.0.1,10.0.0.9') do
          expect(assigner.for('5511900000001')).to be_nil
        end
      end

      expect(log).to include('sumiram do plano datacenter')
      expect(log).to include('10.0.0.9')
      expect(log).to include('atualize a fatia')
    end
  end

  describe 'keeping and replacing' do
    let(:datacenter_list) { [sao_paulo, rio] }

    before { waha_session!('5511900000001', account) }

    it 'keeps the IP already assigned while it is valid on the list' do
      assign_proxy!('5511900000001', rio, account: account)

      expect(assigner.for('5511900000001').address).to eq('10.0.0.1')
    end

    it 'reassigns when the assigned IP left the list or became invalid' do
      assign_proxy!('5511900000001', webshare_proxy(id: 9, address: '10.0.0.9'), account: account, digest: 'old')

      log = capture_log { expect(assigner.for('5511900000001').address).to eq('10.0.0.2') }

      expect(WhatsappProxy::Assignment.last).to have_attributes(proxy_address: '10.0.0.2', credential_digest: nil)
      expect(log).to include('sai de 10.0.0.9:6000')
    end

    it 'leaves an external (hand-made, non Webshare) proxy alone' do
      WhatsappProxy::Assignment.create!(session_name: '5511900000001', account_id: account.id, pool: 'datacenter',
                                        proxy_address: '200.1.1.1', proxy_port: 3128, assigned_at: 1.day.ago)

      expect(assigner.for('5511900000001')).to be_nil
    end
  end

  describe 'engine' do
    let(:datacenter_list) { [sao_paulo, rio, webshare_proxy(id: 5, address: '10.0.0.5', city: 'Campinas')] }

    before { waha_session!('5511900000001', account) }

    it 'skips IPs the engine already uses without a record, keeping only the host' do
      allow(engine).to receive(:list_sessions).with(all: true).and_return(
        [{ 'name' => '5511900000009', 'config' => { 'proxy' => { 'server' => '10.0.0.2:6000', 'password' => 'manual-secret' } } },
         { 'name' => '5511900000008', 'config' => { 'proxy' => { 'server' => 'http://10.0.0.1:6000' } } },
         { 'name' => '5511900000001', 'config' => { 'proxy' => { 'server' => '10.0.0.5:6000' } } }]
      )

      log = capture_log { expect(assigner.for('5511900000001').address).to eq('10.0.0.5') }

      expect(log).not_to include('manual-secret')
    end

    it 'does not reuse an account IP that the engine shows in a session of nobody known' do
      waha_session!('5511900000002', account)
      assign_proxy!('5511900000002', sao_paulo, account: account)
      allow(engine).to receive(:list_sessions).and_return(
        [{ 'name' => '5511900000002', 'config' => { 'proxy' => { 'server' => '10.0.0.2:6000' } } },
         { 'name' => '5511900000077', 'config' => { 'proxy' => { 'server' => '10.0.0.2:6000' } } }]
      )

      expect(assigner.for('5511900000001').address).to eq('10.0.0.1')
    end

    it 'assigns nothing when the engine cannot list its sessions' do
      allow(engine).to receive(:list_sessions).and_raise(Waha::Client::Error, 'down')

      expect(assigner.for('5511900000001')).to be_nil
      expect(WhatsappProxy::Assignment.count).to eq(0)
    end
  end

  describe 'switches and failures' do
    let(:datacenter_list) { [sao_paulo] }

    before { waha_session!('5511900000001', account) }

    it 'stays off, without calling Webshare, unless WHATSAPP_PROXY_ENABLED is "true"' do
      ['false', '1', 'TRUE', nil].each do |value|
        with_modified_env(WHATSAPP_PROXY_ENABLED: value) do
          expect(assigner).not_to be_enabled
          expect(assigner.for('5511900000001')).to be_nil
        end
      end
      expect(WhatsappProxy::Assignment.count).to eq(0)
    end

    it 'returns nil on an unexpected error, logging only the class' do
      allow(WhatsappProxy::SessionOwner).to receive(:find).and_raise(ArgumentError, 'senha-2 vazou?')

      log = capture_log { expect(assigner.for('5511900000001')).to be_nil }

      expect(log).to include('falha inesperada (ArgumentError)')
      expect(log).not_to include('senha-2')
    end

    it 'returns nil without the API key' do
      pools = { isp: WhatsappProxy::Pool.new('isp', client: Webshare::Client.new(pool: :isp, api_key: '')) }
      log = capture_log { expect(described_class.new(engine: engine, pools: pools).for('5511900000001')).to be_nil }

      expect(log).to include('WEBSHARE_API_KEY ausente')
    end

    it 'returns nil when the API is down' do
      client = instance_double(Webshare::Client, configured?: true)
      allow(client).to receive(:proxies).and_raise(Webshare::Client::Error, 'webshare_list_failed status=503')
      pools = { isp: fake_pool('isp', []), datacenter: WhatsappProxy::Pool.new('datacenter', client: client) }

      expect(described_class.new(engine: engine, pools: pools).for('5511900000001')).to be_nil
    end

    it 'records a pending assignment (and alerts) for a new inbox created without proxy (M6)' do
      log = capture_log { assigner.mark_pending!('5511900000001') }

      expect(WhatsappProxy::Assignment.last).to have_attributes(session_name: '5511900000001', pending?: true, pool: 'datacenter')
      expect(log).to include('caixa_sem_proxy')
      expect { assigner.mark_pending!('5511900000001') }.not_to change(WhatsappProxy::Assignment, :count)
    end

    it 'keeps the previous IP when moving a number, to come back to it if the engine refuses (H2)' do
      assign_proxy!('5511900000001', webshare_proxy(id: 9, address: '10.0.0.9'), account: account, digest: 'antigo')

      assigner.for('5511900000001')

      expect(WhatsappProxy::Assignment.last).to have_attributes(proxy_address: '10.0.0.2', previous_proxy_address: '10.0.0.9',
                                                                previous_credential_digest: 'antigo')
    end

    it 'records the credential digest once applied, frees the number on release, and never logs the credential' do
      log = capture_log do
        proxy = assigner.for('5511900000001')
        assigner.mark_applied!('5511900000001', proxy)
        expect(WhatsappProxy::Assignment.last.credential_digest).to eq(proxy.credential_digest)
        expect(proxy.inspect).not_to include('senha-2')
      end
      assigner.release!('5511900000001')

      expect(WhatsappProxy::Assignment.count).to eq(0)
      expect(log).not_to include('senha-')
      expect(log).not_to include('user-')
    end
  end
end

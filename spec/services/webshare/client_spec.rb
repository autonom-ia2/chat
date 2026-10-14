require 'rails_helper'

RSpec.describe Webshare::Client do
  let(:client) { described_class.new(api_key: 'chave-webshare-secreta', plan_id: '42') }
  let(:first_page) { "#{Webshare::Client::LIST_URL}&plan_id=42" }
  let(:second_page) { 'https://proxy.webshare.io/api/v2/proxy/list/?mode=direct&page=2&page_size=100' }

  def stub_page(url, results, next_url: nil, status: 200)
    stub_request(:get, url)
      .with(headers: { 'Authorization' => 'Token chave-webshare-secreta' })
      .to_return(status: status, headers: { 'Content-Type' => 'application/json' },
                 body: { count: results.size, next: next_url, results: results }.to_json)
  end

  it 'lists every page of proxies with the token header' do
    stub_page(first_page, [webshare_api_item(1, '10.0.0.1')], next_url: second_page)
    stub_page(second_page, [webshare_api_item(2, '10.0.0.2', city: 'Sao Paolo')])

    proxies = client.proxies

    expect(proxies.map(&:server)).to eq(['10.0.0.1:6000', '10.0.0.2:6000'])
    expect(proxies.last.city_name).to eq('Sao Paolo')
    expect(proxies.first).to be_valid
  end

  it 'refuses to send the key to a next page outside Webshare' do
    stub_page(first_page, [webshare_api_item(1, '10.0.0.1')], next_url: 'https://evil.example/list')

    expect { client.proxies }.to raise_error(Webshare::Client::Error, 'webshare_unexpected_next_url')
    expect(a_request(:get, 'https://evil.example/list')).not_to have_been_made
  end

  it 'raises without the key, the status or the body in the error' do
    stub_request(:get, first_page).to_return(status: 401, body: 'Invalid token chave-webshare-secreta')

    expect { client.proxies }.to raise_error(Webshare::Client::Error) { |error|
      expect(error.message).to eq('webshare_list_failed status=401')
    }
  end

  it 'turns a timeout into an error' do
    stub_request(:get, first_page).to_raise(Net::OpenTimeout)

    expect { client.proxies }.to raise_error(Webshare::Client::Error, 'webshare_list_failed Net::OpenTimeout')
  end

  describe 'plan of each pool' do
    let(:plans) do
      [{ 'id' => 1, 'proxy_type' => 'shared', 'proxy_subtype' => 'default', 'status' => 'active' },
       { 'id' => 2, 'proxy_type' => 'residential', 'proxy_subtype' => 'residential', 'status' => 'active' },
       { 'id' => 3, 'proxy_type' => 'shared', 'proxy_subtype' => 'isp', 'status' => 'inactive' },
       { 'id' => 4, 'proxy_type' => 'shared', 'proxy_subtype' => 'isp', 'status' => 'active' }]
    end

    def stub_plans(list)
      stub_request(:get, Webshare::Client::PLANS_URL)
        .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: { results: list }.to_json)
    end

    def discovering(pool)
      described_class.new(pool: pool, api_key: 'chave-webshare-secreta', plan_id: '')
    end

    it 'uses the active Static Residential (isp) plan for the isp pool' do
      stub_plans(plans)

      log = capture_log { expect(discovering(:isp).plan_id).to eq('4') }

      expect(log).to include('pool=isp id=4 subtipo=isp')
      expect(log).not_to include('chave-webshare-secreta')
    end

    it 'uses the Proxy Server (default) plan for the datacenter pool' do
      stub_plans(plans)

      expect(discovering(:datacenter).plan_id).to eq('1')
    end

    it 'never falls back to another plan, least of all the rotating residential one' do
      stub_plans(plans.reject { |plan| plan['proxy_subtype'] == 'isp' && plan['status'] == 'active' })

      expect { discovering(:isp).proxies }.to raise_error(Webshare::Client::Error, 'webshare_plan_not_found pool=isp')
    end

    it 'takes the plan of each pool from its own ENV without asking the API' do
      with_modified_env(WEBSHARE_ISP_PLAN_ID: '77', WEBSHARE_DATACENTER_PLAN_ID: '88') do
        expect(described_class.new(pool: :isp, api_key: 'x').plan_id).to eq('77')
        expect(described_class.new(pool: :datacenter, api_key: 'x').plan_id).to eq('88')
      end
      expect(a_request(:get, Webshare::Client::PLANS_URL)).not_to have_been_made
    end

    it 'lists the proxies of the discovered plan' do
      stub_plans(plans)
      stub_page("#{Webshare::Client::LIST_URL}&plan_id=4", [webshare_api_item(1, '10.0.0.1')])

      expect(discovering(:isp).proxies.map(&:server)).to eq(['10.0.0.1:6000'])
    end
  end

  it 'is not configured without the key and never shows it in inspect' do
    expect(described_class.new(api_key: '')).not_to be_configured
    expect(client.inspect).not_to include('chave-webshare-secreta')
  end
end

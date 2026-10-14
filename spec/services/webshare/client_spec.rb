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

  describe 'plan of the pool' do
    let(:discovering) { described_class.new(api_key: 'chave-webshare-secreta', plan_id: '') }

    def stub_plans(plans)
      stub_request(:get, Webshare::Client::PLANS_URL)
        .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: { results: plans }.to_json)
    end

    it 'prefers the active Static Residential (isp) plan and never the rotating residential one' do
      stub_plans([{ 'id' => 1, 'proxy_type' => 'shared', 'proxy_subtype' => 'default', 'status' => 'active' },
                  { 'id' => 2, 'proxy_type' => 'residential', 'proxy_subtype' => 'residential', 'status' => 'active' },
                  { 'id' => 3, 'proxy_type' => 'shared', 'proxy_subtype' => 'isp', 'status' => 'inactive' },
                  { 'id' => 4, 'proxy_type' => 'shared', 'proxy_subtype' => 'isp', 'status' => 'active' }])

      log = capture_log { expect(discovering.plan_id).to eq('4') }

      expect(log).to include('plano da Webshare id=4 subtipo=isp')
      expect(log).not_to include('chave-webshare-secreta')
    end

    it 'falls back to the default plan when there is no isp plan' do
      stub_plans([{ 'id' => 2, 'proxy_type' => 'residential', 'proxy_subtype' => 'residential' },
                  { 'id' => 1, 'proxy_type' => 'shared', 'proxy_subtype' => 'default' }])

      expect(discovering.plan_id).to eq('1')
    end

    it 'refuses to use the residential plan alone' do
      stub_plans([{ 'id' => 2, 'proxy_type' => 'residential', 'proxy_subtype' => 'residential' }])

      expect { discovering.proxies }.to raise_error(Webshare::Client::Error, 'webshare_plan_not_found')
    end

    it 'uses WEBSHARE_PLAN_ID without asking the API' do
      stub_page(first_page, [webshare_api_item(1, '10.0.0.1')])

      client.proxies

      expect(a_request(:get, Webshare::Client::PLANS_URL)).not_to have_been_made
    end

    it 'lists the proxies of the discovered plan' do
      stub_plans([{ 'id' => 4, 'proxy_type' => 'shared', 'proxy_subtype' => 'isp' }])
      stub_page("#{Webshare::Client::LIST_URL}&plan_id=4", [webshare_api_item(1, '10.0.0.1')])

      expect(discovering.proxies.map(&:server)).to eq(['10.0.0.1:6000'])
    end
  end

  it 'is not configured without the key and never shows it in inspect' do
    expect(described_class.new(api_key: '')).not_to be_configured
    expect(client.inspect).not_to include('chave-webshare-secreta')
  end
end

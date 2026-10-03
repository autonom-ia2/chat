require 'rails_helper'

RSpec.describe Instagram::Testers::Client do
  subject(:client) { described_class.new(configuration: configuration) }

  let(:configuration) do
    instance_double(Instagram::Testers::Configuration, app_id: '10001', business_id: '10002', doc_id: '10003', session: session,
                                                       session_snapshot: { session: session, version: nil },
                                                       transport_options: { http_proxyaddr: nil, max_retries: 0 })
  end
  let(:session) do
    { 'cookie' => 'synthetic=fixture', 'user_agent' => 'Synthetic Client', 'user_id' => '12345',
      'fb_dtsg' => 'synthetic-dtsg', 'lsd' => 'synthetic-lsd', 'jazoest' => '1234', 'extra_form' => { '__req' => '1' } }
  end
  let(:target_id) { '17841400000000001' }
  let(:search_url) { 'https://developers.facebook.com/roles/instagram/typeahead/user/?value=%40demo_company' }
  let(:roles_url) { 'https://developers.facebook.com/api/graphql/' }
  let(:invite_url) { 'https://developers.facebook.com/apps/10001/async/instagram/roles/add/' }

  let(:base_form) do
    { '__a' => '1', '__user' => '12345', '__bid' => '10002', 'fb_dtsg' => 'synthetic-dtsg',
      'lsd' => 'synthetic-lsd', 'jazoest' => '1234', '__req' => '1' }
  end
  let(:observed_headers) do
    { 'Cookie' => 'synthetic=fixture', 'User-Agent' => 'Synthetic Client', 'X-FB-LSD' => 'synthetic-lsd',
      'Origin' => 'https://developers.facebook.com',
      'Referer' => 'https://developers.facebook.com/apps/10001/roles/roles/?business_id=10002',
      'Content-Type' => 'application/x-www-form-urlencoded' }
  end

  it 'posts typeahead with the encoded username in the URL query and the exact observed session form' do
    request = stub_request(:post, search_url).with(body: base_form, headers: observed_headers)
                                             .to_return(status: 200, body: 'for (;;);{"payload":{"entries":[]}}')
    expect(HTTParty).to receive(:post).with(search_url, body: base_form, headers: observed_headers,
                                                        timeout: described_class::TIMEOUT, follow_redirects: false,
                                                        http_proxyaddr: nil, max_retries: 0).and_call_original
    expect(client.search('demo_company')).to eq([])
    expect(request).to have_been_requested.once
    expect(a_request(:post, invite_url)).not_to have_been_made
  end

  it 'posts GraphQL with av, RelayModern, the configured parent app and friendly name in body and header' do
    form = base_form.merge('av' => '12345', 'fb_api_caller_class' => 'RelayModern', 'fb_api_req_friendly_name' => 'RolesTable_Query',
                           'doc_id' => '10003', 'variables' => '{"app_id":"10001"}')
    headers = observed_headers.merge('X-FB-Friendly-Name' => 'RolesTable_Query')
    request = stub_request(:post, roles_url).with(body: form, headers: headers)
                                            .to_return(status: 200, body: { data: { get_app_roles: { app_roles: [
                                              { role: 'instagram testers', users: [{ id: target_id, name: 'Synthetic company',
                                                                                     role: 'instagram testers', status: 'CONFIRMED' }] }
                                            ] } } }.to_json)
    expect(HTTParty).to receive(:post).with(roles_url, body: form, headers: headers,
                                                       timeout: described_class::TIMEOUT, follow_redirects: false,
                                                       http_proxyaddr: nil, max_retries: 0).and_call_original
    expect(client.status(target_id)).to eq('accepted')
    expect(request).to have_been_requested.once
    expect(a_request(:post, invite_url)).not_to have_been_made
  end

  it 'posts the exact observed invite form and headers, preserving the selected string ID' do
    form = base_form.merge('role' => 'instagram testers', 'user_id_or_vanitys[0]' => target_id, 'reload_on_success' => 'false')
    expected_body = base_form.merge('role' => 'instagram testers', 'user_id_or_vanitys' => [target_id], 'reload_on_success' => 'false')
    request = stub_request(:post, invite_url).with(body: expected_body, headers: observed_headers)
                                             .to_return(status: 200, body: 'for (;;);{"payload":{"success":true}}')
    expect(HTTParty).to receive(:post).with(invite_url, body: form, headers: observed_headers,
                                                        timeout: described_class::TIMEOUT, follow_redirects: false,
                                                        http_proxyaddr: nil, max_retries: 0).and_call_original
    expect(client.invite(target_id)).to be true
    expect(request).to have_been_requested.once
  end

  [nil, 'true', 1].each do |success|
    it "does not accept ambiguous invite success #{success.inspect}" do
      stub_request(:post, invite_url).to_return(status: 200, body: { payload: { success: success } }.to_json)
      expect { client.invite(target_id) }.to(raise_error { |error| expect(error.code).to eq('invite_unknown') })
    end
  end

  it 'reports an explicit boolean rejection' do
    stub_request(:post, invite_url).to_return(status: 200, body: '{"payload":{"success":false}}')
    expect { client.invite(target_id) }.to(raise_error { |error| expect(error.code).to eq('invite_rejected') })
  end

  it 'keeps a transport timeout indeterminate and strips the provider exception cause' do
    stub_request(:post, invite_url).to_raise(Net::ReadTimeout.new('synthetic sensitive provider content'))
    expect { client.invite(target_id) }.to raise_error do |error|
      expect(error.code).to eq('invite_unknown')
      expect(error.message).to eq('invite_unknown')
      expect(error.cause).to be_nil
    end
  end

  [301, 500].each do |http_status|
    it "does not interpret status #{http_status} as expired or successful" do
      stub_request(:post, search_url).to_return(status: http_status, body: 'synthetic', headers: { 'Location' => 'https://example.com/' })
      expect { client.search('demo_company') }.to(raise_error { |error| expect(error.code).to eq('meta_unavailable') })
      expect(a_request(:post, 'https://example.com/')).not_to have_been_made
    end
  end

  it 'reports concrete authentication failures and provider read throttling' do
    stub_request(:post, search_url).to_return(status: 401)
    expect { client.search('demo_company') }.to(raise_error { |error| expect(error.code).to eq('meta_session_expired') })
    stub_request(:post, search_url).to_return(status: 429)
    expect { client.search('demo_company') }.to(raise_error { |error| expect(error.code).to eq('rate_limited') })
  end

  it 'does not interpret HTML or partial GraphQL errors as absence' do
    stub_request(:post, roles_url).to_return(status: 200, body: '<html>synthetic login</html>')
    expect { client.status(target_id) }.to(raise_error { |error| expect(error.code).to eq('unknown_status') })
    stub_request(:post, roles_url).to_return(status: 200, body: '{"errors":[{}],"data":{"get_app_roles":{"app_roles":[]}}}')
    expect { client.status(target_id) }.to(raise_error { |error| expect(error.code).to eq('unknown_status') })
  end

  it 'uses one coherent snapshot for cookie, headers and form even when another session is published concurrently' do
    expect(configuration).to receive(:session_snapshot).once.and_return(session: session, version: nil)
    expect(configuration).not_to receive(:session)
    stub_request(:post, roles_url).with(body: base_form.merge('av' => '12345', 'fb_api_caller_class' => 'RelayModern',
                                                              'fb_api_req_friendly_name' => 'RolesTable_Query', 'doc_id' => '10003',
                                                              'variables' => '{"app_id":"10001"}'), headers: observed_headers)
                                  .to_return(status: 200, body: '{"data":{"get_app_roles":{"app_roles":[]}}}')
    expect(client.status(target_id)).to eq('absent')
  end

  [401, 403].each do |status|
    it "invalidates only the rejected managed version on HTTP #{status} and never retries" do
      allow(configuration).to receive(:session_snapshot).and_return(session: session, version: 'synthetic-version')
      store = instance_double(Instagram::Testers::SessionStore)
      allow(Instagram::Testers::SessionStore).to receive(:new).with(configuration: configuration).and_return(store)
      expect(store).to receive(:invalidate).with(version: 'synthetic-version', code: "http_#{status}")
      request = stub_request(:post, search_url).to_return(status: status)
      expect { client.search('demo_company') }.to(raise_error { |error| expect(error.code).to eq('meta_session_expired') })
      expect(request).to have_been_requested.once
    end
  end

  it 'does not make a request when the managed session is missing or invalidated' do
    allow(configuration).to receive(:session_snapshot).and_return(session: nil, version: nil)
    expect(HTTParty).not_to receive(:post)
    expect { client.search('demo_company') }.to(raise_error { |error| expect(error.code).to eq('meta_session_expired') })
  end

  context 'with a real local CONNECT proxy and IP authorization' do
    let(:proxy_state) { {} }

    before do
      stub_const('Instagram::Testers::Client::HOST', 'https://127.0.0.1:1')
      WebMock.allow_net_connect!(allow_localhost: true)
      proxy_state[:server] = TCPServer.new('127.0.0.1', 0)
      allow(configuration).to receive(:transport_options).and_return(http_proxyaddr: '127.0.0.1',
                                                                     http_proxyport: proxy_state[:server].addr[1],
                                                                     http_proxyuser: nil, http_proxypass: nil, max_retries: 0)
    end

    after do
      proxy_state[:server].close
      proxy_state[:thread]&.kill
      proxy_state[:thread]&.join
      WebMock.disable_net_connect!(allow_localhost: true)
    end

    it 'classifies CONNECT 407 without forwarding to the destination or sending proxy credentials' do
      proxy_state[:thread] = Thread.new do
        socket = proxy_state[:server].accept
        proxy_state[:connect_line] = socket.gets
        proxy_state[:authorization_seen] = false
        socket.each_line do |line|
          break if line == "\r\n"

          proxy_state[:authorization_seen] ||= line.start_with?('Proxy-Authorization:') # Record a boolean, never headers.
        end
        socket.write("HTTP/1.1 407 Proxy Authentication Required\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
        socket.close
      end
      expect { client.search('demo_company') }.to raise_error do |error|
        expect(error.code).to eq('proxy_unavailable')
        expect(error.cause).to be_nil
      end
      expect(proxy_state[:connect_line]).to eq("CONNECT 127.0.0.1:1 HTTP/1.1\r\n")
      expect(proxy_state[:authorization_seen]).to be false
    end

    it 'preserves an ambiguous invitation on CONNECT timeout without direct fallback or retry' do
      stub_const('Instagram::Testers::Client::TIMEOUT', 0.05)
      proxy_state[:thread] = Thread.new do
        socket = proxy_state[:server].accept
        proxy_state[:connect_line] = socket.gets
        sleep 1
        socket.close
      end
      expect { client.invite(target_id) }.to raise_error do |error|
        expect(error.code).to eq('invite_unknown')
        expect(error.cause).to be_nil
      end
      expect(proxy_state[:connect_line]).to start_with('CONNECT 127.0.0.1:1 ')
    end
  end
end

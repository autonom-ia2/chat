require 'rails_helper'

RSpec.describe Instagram::Testers::Client do
  subject(:client) { described_class.new(configuration: configuration) }

  let(:configuration) do
    instance_double(Instagram::Testers::Configuration, app_id: '10001', business_id: '10002', doc_id: '10003', session: session)
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
                                                        timeout: described_class::TIMEOUT, follow_redirects: false).and_call_original
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
                                                       timeout: described_class::TIMEOUT, follow_redirects: false).and_call_original
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
                                                        timeout: described_class::TIMEOUT, follow_redirects: false).and_call_original
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

  [301, 403, 500].each do |http_status|
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
end

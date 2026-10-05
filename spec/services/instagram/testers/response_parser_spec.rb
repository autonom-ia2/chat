require 'rails_helper'

RSpec.describe Instagram::Testers::ResponseParser do
  let(:target_id) { '17841400000000001' }
  let(:entry) { { 'uniqueID' => target_id, 'text' => 'demo_company', 'subtitle' => 'Synthetic company', 'photo' => 'https://example.com/photo.png' } }
  let(:tester) { { 'id' => target_id, 'status' => 'PENDING' } }
  let(:groups) { [{ 'role' => 'instagram testers', 'users' => [tester] }] }
  let(:document) { { 'data' => { 'get_app_roles' => { 'app_roles' => groups } } } }

  it 'parses Meta prefixed JSON without executing the response' do
    body = { payload: { entries: [entry] } }.to_json
    parsed = described_class.parse("for (;;);#{body}", error_code: 'meta_unavailable')
    expect(described_class.candidates(parsed)).to eq([{ id: target_id, username: 'demo_company', name: 'Synthetic company',
                                                        avatar_url: 'https://example.com/photo.png' }])
  end

  it 'canonicalizes mixed-case usernames before signing and returning candidates' do
    entry['text'] = 'Demo_Company'
    expect(described_class.candidates('payload' => { 'entries' => [entry] }).first[:username]).to eq('demo_company')
  end

  ['<html>Login</html>', '{}', '[]', '{"error":1357004}', '{"errors":[{"message":"synthetic"}]}'].each do |body|
    it "rejects broken typeahead response #{body}" do
      expect do
        parsed = described_class.parse(body, error_code: 'meta_unavailable')
        described_class.candidates(parsed)
      end.to(raise_error { |error| expect(error.code).to eq('meta_unavailable') })
    end
  end

  it 'rejects malformed or duplicate candidates as a complete response' do
    [entry.merge('uniqueID' => 17_841_400_000_000_001), entry.merge('photo' => 'javascript:synthetic'),
     entry.merge('text' => 'bad/name')].each do |bad_entry|
      expect { described_class.candidates('payload' => { 'entries' => [entry, bad_entry] }) }
        .to(raise_error { |error| expect(error.code).to eq('meta_unavailable') })
    end
    expect { described_class.candidates('payload' => { 'entries' => [entry, entry] }) }
      .to(raise_error { |error| expect(error.code).to eq('meta_unavailable') })
  end

  it 'returns pending and accepted only for exact IDs' do
    expect(described_class.status(document, target_id)).to eq('pending')
    tester['status'] = 'CONFIRMED'
    expect(described_class.status(document, target_id)).to eq('accepted')
    expect(described_class.status(document, '17841400000000002')).to eq('absent')
  end

  it 'searches every same-role group including empty groups' do
    groups.unshift({ 'role' => 'instagram testers', 'users' => [] }, { 'role' => 'admin', 'users' => [tester.merge('status' => 'CONFIRMED')] })
    expect(described_class.status(document, target_id)).to eq('pending')
  end

  it 'rejects conflicting statuses across duplicate role groups' do
    groups << { 'role' => 'instagram testers', 'users' => [tester.merge('status' => 'CONFIRMED')] }
    expect { described_class.status(document, target_id) }.to(raise_error { |error| expect(error.code).to eq('unknown_status') })
  end

  it 'accepts repeated same-role groups agreeing on the status' do
    groups << { 'role' => 'instagram testers', 'users' => [tester.dup] }
    expect(described_class.status(document, target_id)).to eq('pending')
  end

  it 'requires valid statuses even for unrelated testers before declaring absence' do
    tester['status'] = 'UNKNOWN'
    expect { described_class.status(document, '99999') }.to(raise_error { |error| expect(error.code).to eq('unknown_status') })
  end

  it 'rejects incomplete schema and pagination' do
    [nil, {}, { 'data' => nil }, { 'data' => { 'get_app_roles' => {} } }].each do |bad_document|
      expect do
        parsed = described_class.parse(bad_document.to_json, error_code: 'unknown_status')
        described_class.status(parsed, target_id)
      end.to(raise_error { |error| expect(error.code).to eq('unknown_status') })
    end
    groups.first['page_info'] = { 'has_next_page' => true }
    expect { described_class.status(document, target_id) }.to(raise_error { |error| expect(error.code).to eq('unknown_status') })
  end

  it 'rejects GraphQL errors even when data includes a confirmed tester' do
    tester['status'] = 'CONFIRMED'
    document['errors'] = [{ 'message' => 'synthetic partial error' }]
    expect { described_class.parse(document.to_json, error_code: 'unknown_status') }
      .to(raise_error { |error| expect(error.code).to eq('unknown_status') })
  end

  it 'rejects conflicting statuses for other users before declaring target absence' do
    tester['id'] = '99999'
    groups << { 'role' => 'instagram testers', 'users' => [tester.merge('status' => 'CONFIRMED')] }
    expect { described_class.status(document, target_id) }.to(raise_error { |error| expect(error.code).to eq('unknown_status') })
  end

  it 'rejects nested provider errors despite an otherwise complete schema' do
    document['data']['get_app_roles']['errors'] = [{ 'message' => 'synthetic nested failure' }]
    expect { described_class.parse(document.to_json, error_code: 'unknown_status') }
      .to(raise_error { |error| expect(error.code).to eq('unknown_status') })
  end
end

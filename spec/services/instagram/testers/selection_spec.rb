require 'rails_helper'

RSpec.describe Instagram::Testers::Selection do
  subject(:selection) { described_class.new(account_id: 16, actor_id: 2, app_id: '10001') }

  around do |example|
    with_modified_env('FRONTEND_URL' => 'https://autonomia.example') { example.run }
  end

  let(:candidate) { { id: '17841400000000001', username: 'demo_company' } }
  let(:token) { selection.issue(candidate) }

  it 'preserves the exact long ID and returned username' do
    expect(selection.verify(token)).to eq('id' => candidate[:id], 'username' => candidate[:username], 'app_id' => '10001',
                                          'account_id' => '16', 'actor_id' => '2', 'installation' => Instagram::Testers::OauthBinding.installation)
  end

  it 'binds selection to the account, actor and parent app' do
    [{ account_id: 17, actor_id: 2, app_id: '10001' }, { account_id: 16, actor_id: 3, app_id: '10001' },
     { account_id: 16, actor_id: 2, app_id: '10002' }].each do |scope|
      expect { described_class.new(**scope).verify(token) }.to raise_error do |error|
        expect(error.code).to eq('invalid_selection')
      end
    end
  end

  it 'rejects selection issued by another installation even with identical account, actor and app' do
    issued = with_modified_env('FRONTEND_URL' => 'https://autonomia.example') { selection.issue(candidate) }
    with_modified_env('FRONTEND_URL' => 'https://hub2you.example') do
      other = described_class.new(account_id: 16, actor_id: 2, app_id: '10001')
      expect { other.verify(issued) }.to raise_error do |error|
        expect(error.code).to eq('invalid_selection')
      end
    end
  end

  it 'rejects tampering and undocumented client types' do
    ["#{token}tampered", nil, 12, { id: candidate[:id] }].each do |value|
      expect { selection.verify(value) }.to raise_error do |error|
        expect(error.code).to eq('invalid_selection')
      end
    end
  end

  it 'expires after two hours' do
    issued_token = token
    travel 2.hours + 1.second do
      expect { selection.verify(issued_token) }.to raise_error do |error|
        expect(error.code).to eq('invalid_selection')
      end
    end
  end
end

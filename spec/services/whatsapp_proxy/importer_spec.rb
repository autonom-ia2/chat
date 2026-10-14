require 'rails_helper'

RSpec.describe WhatsappProxy::Importer do
  let(:webshare) { instance_double(Webshare::Client) }
  let(:output) { StringIO.new }
  let(:entries) do
    [
      { 'session' => '5511900000001', 'webshare_id' => '1', 'host' => '10.0.0.1', 'port' => '6000', 'engine' => 'hubsegs (Hub2You)' },
      { 'session' => 'hybrid-5511900000002', 'webshare_id' => nil, 'host' => '10.0.0.2', 'port' => '6000',
        'engine' => 'hubsegs (Hub2You)' },
      { 'session' => '5511900000003', 'webshare_id' => '3', 'host' => '10.0.0.3', 'port' => '6000',
        'engine' => 'autonomia (Autonom.ia)' }
    ]
  end
  let(:proxies) { [webshare_proxy(id: 1, address: '10.0.0.1'), webshare_proxy(id: 2, address: '10.0.0.2')] }

  before { allow(webshare).to receive(:proxies).and_return(proxies) }

  def import
    described_class.new(entries: entries, engine: 'hubsegs', client: webshare, output: output).perform
  end

  it 'imports only the lines of this engine, resolving the missing Webshare id by host, with the current credential digest' do
    result = import

    expect(result.to_h).to eq(imported: 2, unchanged: 0, skipped: 0)
    expect(WhatsappProxy::Assignment.pluck(:session_name)).to contain_exactly('5511900000001', 'hybrid-5511900000002')
    hybrid = WhatsappProxy::Assignment.find_by!(session_name: 'hybrid-5511900000002')
    expect(hybrid.webshare_proxy_id).to eq('2')
    expect(hybrid.credential_digest).to eq(proxies.last.credential_digest)
    expect(output.string).not_to include('senha-')
  end

  it 'is idempotent' do
    import

    expect(import.to_h).to eq(imported: 0, unchanged: 2, skipped: 0)
    expect(WhatsappProxy::Assignment.count).to eq(2)
  end

  it 'keeps a line outside Webshare as an external reservation' do
    allow(webshare).to receive(:proxies).and_return([proxies.first])

    import

    expect(WhatsappProxy::Assignment.find_by!(session_name: 'hybrid-5511900000002')).to be_external
  end

  it 'skips an IP already assigned to another session' do
    WhatsappProxy::Assignment.create!(session_name: 'outra', proxy_address: '10.0.0.1', proxy_port: 6000, assigned_at: Time.current)

    expect(import.to_h).to eq(imported: 1, unchanged: 0, skipped: 1)
    expect(output.string).to include('já atribuído a outra')
  end
end

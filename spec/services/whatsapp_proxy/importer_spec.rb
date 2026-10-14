require 'rails_helper'

RSpec.describe WhatsappProxy::Importer do
  let(:account) { create(:account) }
  let(:output) { StringIO.new }
  let(:datacenter_list) { [webshare_proxy(id: 1, address: '10.0.0.1'), webshare_proxy(id: 2, address: '10.0.0.2')] }
  let(:isp_list) { [webshare_proxy(id: 50, address: '10.5.0.1')] }
  let(:entries) do
    [
      { 'session' => '5511900000001', 'webshare_id' => '1', 'host' => '10.0.0.1', 'port' => '6000',
        'engine' => 'hubsegs (Hub2You)', 'plano' => 'proxy_server_datacenter_br' },
      { 'session' => 'hybrid-5511900000002', 'webshare_id' => nil, 'host' => '10.0.0.2', 'port' => '6000',
        'engine' => 'hubsegs (Hub2You)', 'plano' => 'proxy_server_datacenter_br' },
      { 'session' => 'hybrid-5511900000004', 'webshare_id' => '50', 'host' => '10.5.0.1', 'port' => '6000',
        'engine' => 'hubsegs (Hub2You)', 'plano' => 'static_residential_isp' },
      { 'session' => '5511900000003', 'webshare_id' => '3', 'host' => '10.0.0.3', 'port' => '6000',
        'engine' => 'autonomia (Autonom.ia)', 'plano' => 'proxy_server_datacenter_br' }
    ]
  end

  before do
    waha_session!('5511900000001', account)
    hybrid_session!('hybrid-5511900000002', account)
    hybrid_session!('hybrid-5511900000004', account)
  end

  def import
    pools = { datacenter: fake_pool('datacenter', datacenter_list), isp: fake_pool('isp', isp_list) }
    described_class.new(entries: entries, engine: 'hubsegs', pools: pools, output: output).perform
  end

  it 'imports only this engine lines, with the account of the session, the plan of the line and the current digest' do
    result = import

    expect(result.to_h).to eq(imported: 3, unchanged: 0, skipped: 0)
    expect(WhatsappProxy::Assignment.pluck(:session_name, :pool, :account_id)).to contain_exactly(
      ['5511900000001', 'datacenter', account.id], ['hybrid-5511900000002', 'datacenter', account.id],
      ['hybrid-5511900000004', 'isp', account.id]
    )
    hybrid = WhatsappProxy::Assignment.find_by!(session_name: 'hybrid-5511900000002')
    expect(hybrid.webshare_proxy_id).to eq('2')
    expect(hybrid.credential_digest).to eq(datacenter_list.last.credential_digest)
    expect(output.string).not_to include('senha-')
  end

  it 'is idempotent' do
    import

    expect(import.to_h).to eq(imported: 0, unchanged: 3, skipped: 0)
    expect(WhatsappProxy::Assignment.count).to eq(3)
  end

  it 'keeps a line outside Webshare as an external reservation' do
    datacenter_list.pop

    import

    expect(WhatsappProxy::Assignment.find_by!(session_name: 'hybrid-5511900000002')).to be_external
  end

  it 'skips a session that has no inbox in this stack and an unknown plan' do
    entries << { 'session' => '5511900000099', 'host' => '10.0.0.9', 'port' => '6000', 'engine' => 'hubsegs (Hub2You)',
                 'plano' => 'proxy_server_datacenter_br' }
    entries << { 'session' => '5511900000001', 'host' => '10.0.0.9', 'port' => '6000', 'engine' => 'hubsegs (Hub2You)',
                 'plano' => 'residential' }

    expect(import.to_h).to eq(imported: 3, unchanged: 0, skipped: 2)
    expect(output.string).to include('sessão sem caixa nesta stack', 'plano desconhecido: residential')
  end

  it 'skips an IP that belongs to another account' do
    WhatsappProxy::Assignment.create!(session_name: 'outra', account_id: create(:account).id, pool: 'datacenter',
                                      proxy_address: '10.0.0.1', proxy_port: 6000, assigned_at: Time.current)

    expect(import.to_h).to eq(imported: 2, unchanged: 0, skipped: 1)
    expect(output.string).to include('já é de outra conta')
  end
end

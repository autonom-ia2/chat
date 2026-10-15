require 'rails_helper'

# #1487: o Guia diz que o WhatsApp API está pausado pelo administrador, sem tratar como queda.
describe Autonomia::Guide::Diagnostics do
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:account) { channel.account }
  let(:user) { create(:user, account: account, role: :administrator) }
  let!(:connection) do
    WhatsappHybrid::Connection.create!(account: account, inbox: channel.inbox, session_name: 'hybrid-diag', status: 'disconnected')
  end

  def findings
    described_class.run('channel', account: account, user: user).select { |text| text.include?('WhatsApp API da caixa oficial') }
  end

  it 'reports a paused connection as information, with how to resume' do
    connection.update!(paused_at: Time.current)

    expect(findings.size).to eq(1)
    expect(findings.first).to include('pausado pelo administrador', 'Retomar')
  end

  it 'keeps reporting a dropped connection as disconnected' do
    expect(findings.size).to eq(1)
    expect(findings.first).to include('desconectado')
  end

  it 'says nothing when connected' do
    connection.update!(status: 'connected')

    expect(findings).to be_empty
  end
end

require 'rails_helper'

RSpec.describe WhatsappProxy::Alert do
  before { %w[plano_esgotado: x:].each { |key| Redis::Alfred.delete("whatsapp_proxy:alert:#{key}") } }

  it 'sends a grouped warning to Sentry when it is configured, and always logs' do
    sentry = Module.new { def self.capture_message(*, **) = nil }
    stub_const('Sentry', sentry)
    allow(sentry).to receive(:capture_message)

    log = capture_log do
      with_modified_env(SENTRY_DSN: 'https://example.invalid/1') { described_class.notify!('plano_esgotado', 'plano isp sem IP', level: :error) }
    end

    expect(sentry).to have_received(:capture_message)
      .with('[whatsapp_proxy] plano_esgotado: plano isp sem IP', level: :error, fingerprint: %w[whatsapp_proxy plano_esgotado])
    expect(log).to include('[whatsapp_proxy][alerta] plano_esgotado: plano isp sem IP')
  end

  it 'only logs without Sentry' do
    log = capture_log { with_modified_env(SENTRY_DSN: nil) { described_class.notify!('troca_desfeita', 'x') } }

    expect(log).to include('troca_desfeita')
  end

  it 'never breaks the caller when Sentry fails' do
    sentry = Module.new { def self.capture_message(*, **) = raise(StandardError) }
    stub_const('Sentry', sentry)

    expect { with_modified_env(SENTRY_DSN: 'https://example.invalid/1') { described_class.notify!('x', 'y') } }.not_to raise_error
  end

  describe 'platform account (WHATSAPP_PROXY_ALERT_ACCOUNT_ID)' do
    let(:platform) { create(:account) }
    let!(:admin) { create(:user, account: platform, role: :administrator) }
    let(:client_account) { create(:account) }
    let(:channel) { waha_session!('5511987654321', client_account) }

    before do
      create(:user, account: client_account, role: :administrator)
      Redis::Alfred.delete('whatsapp_proxy:alert:troca_desfeita:5511987654321')
    end

    def avisos(account)
      Autonomia::Guide::Aviso.where(account: account)
    end

    it 'warns the platform admins, never the client account, with inbox/account numbers and a masked IP only' do
      channel
      with_modified_env(WHATSAPP_PROXY_ALERT_ACCOUNT_ID: platform.id.to_s) do
        described_class.notify!('troca_desfeita', 'detalhe técnico com 5511987654321',
                                level: :error, session: '5511987654321', ip: '10.20.30.40:6000')
      end

      aviso = avisos(platform).sole
      expect(aviso).to have_attributes(user_id: admin.id, gravidade: 'urgente')
      expect(aviso.texto).to include("inbox #{channel.inbox.id}", "account #{client_account.id}", '10.20.x.x')
      expect(aviso.texto).not_to include('5511987654321', '10.20.30.40')
      expect(avisos(client_account)).to be_empty
    end

    it 'only logs without the variable' do
      channel
      log = capture_log do
        with_modified_env(WHATSAPP_PROXY_ALERT_ACCOUNT_ID: nil) { described_class.notify!('troca_desfeita', 'x', session: '5511987654321') }
      end

      expect(Autonomia::Guide::Aviso.count).to eq(0)
      expect(log).to include('troca_desfeita')
    end

    it 'sends the same alert at most once per hour (the log keeps every one)' do
      channel
      log = capture_log do
        with_modified_env(WHATSAPP_PROXY_ALERT_ACCOUNT_ID: platform.id.to_s) do
          3.times { described_class.notify!('troca_desfeita', 'x', level: :error, session: '5511987654321') }
        end
      end

      expect(avisos(platform).count).to eq(1)
      expect(log.scan('troca_desfeita').size).to eq(3)
    end
  end
end

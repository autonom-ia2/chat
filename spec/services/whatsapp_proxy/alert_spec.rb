require 'rails_helper'

RSpec.describe WhatsappProxy::Alert do
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
end

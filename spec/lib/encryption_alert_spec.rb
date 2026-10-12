require 'rails_helper'

# #1344 — produção sem chaves de criptografia avisa no log e no Sentry, em vez de gravar segredo em claro calada.
RSpec.describe EncryptionAlert do
  let(:tracker) { instance_double(ChatwootExceptionTracker, capture_exception: true) }

  before { allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker) }

  def rodar(producao:, chaves:)
    allow(Rails.env).to receive(:production?).and_return(producao)
    allow(Chatwoot).to receive(:encryption_configured?).and_return(chaves)
    described_class.check
  end

  it 'avisa em produção sem chaves', :aggregate_failures do
    rodar(producao: true, chaves: false)

    expect(ChatwootExceptionTracker).to have_received(:new).with(an_instance_of(described_class::KeysMissing))
    expect(tracker).to have_received(:capture_exception)
  end

  it 'fica calado em produção com chaves' do
    rodar(producao: true, chaves: true)

    expect(ChatwootExceptionTracker).not_to have_received(:new)
  end

  it 'fica calado fora de produção' do
    rodar(producao: false, chaves: false)

    expect(ChatwootExceptionTracker).not_to have_received(:new)
  end
end

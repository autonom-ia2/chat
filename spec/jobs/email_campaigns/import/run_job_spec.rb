require 'rails_helper'

# O job da importação (#1099, entrega B): pega a trava antes de trabalhar, não disputa com outro worker, registra só o
# código da falha e solta a entrada recebida no fim.
RSpec.describe EmailCampaigns::Import::RunJob, :aggregate_failures do
  let(:account) { create(:account) }
  let(:import) do
    EmailCampaignTemplateImport.create!(account: account, source_kind: 'paste').tap do |record|
      record.source.attach(io: StringIO.new('<p>Olá</p>'), filename: 'modelo.html', content_type: 'text/html')
    end
  end

  around do |example|
    with_modified_env FRONTEND_URL: 'https://app.exemplo.com.br' do
      example.run
    end
  end

  it 'runs on the medium queue' do
    expect(described_class.new.queue_name).to eq('medium')
  end

  it 'imports and releases the received input' do
    described_class.perform_now(import.id)

    expect(import.reload).to have_attributes(status: 'ready', attempts: 1, locked_until: nil)
    expect(import.result_mjml).to include('Olá')
    expect(import.source).not_to be_attached
  end

  it 'leaves alone an import another worker holds' do
    import.claim!
    allow(EmailCampaigns::Import::Run).to receive(:call)

    described_class.perform_now(import.id)

    expect(EmailCampaigns::Import::Run).not_to have_received(:call)
    expect(import.reload.status).to eq('processing')
  end

  it 'turns an unexpected error into the internal code without the message' do
    allow(EmailCampaigns::Import::Engine).to receive(:call).and_raise(RuntimeError, '<script>segredo do cliente</script>')
    allow(Rails.logger).to receive(:error)

    described_class.perform_now(import.id)

    expect(import.reload).to have_attributes(status: 'failed', error_code: 'internal')
    expect(Rails.logger).to have_received(:error).with(satisfy { |line| line.exclude?('segredo') && line.include?('RuntimeError') })
    expect(import.source).not_to be_attached
  end

  it 'stops when the whole job goes past its 90 seconds' do
    clock = [0.0]
    allow(Process).to receive(:clock_gettime).and_call_original
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { clock[0] }
    allow(EmailCampaigns::Import::Engine).to receive(:call).and_wrap_original do |original, *args, **kwargs|
      clock[0] += 91
      original.call(*args, **kwargs)
    end

    described_class.perform_now(import.id)

    expect(import.reload).to have_attributes(status: 'failed', error_code: 'too_slow')
  end
end

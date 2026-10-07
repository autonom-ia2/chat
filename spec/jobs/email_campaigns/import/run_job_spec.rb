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

  it 'turns an unexpected error into the internal code, traceable but without the client content' do
    allow(EmailCampaigns::Import::Engine).to receive(:call).and_raise(RuntimeError, '<script>segredo do cliente</script>')
    logged = []
    allow(Rails.logger).to receive(:error) { |line| logged << line }
    tracked = []
    allow(ChatwootExceptionTracker).to receive(:new).and_wrap_original do |original, error, **options|
      tracked << [error, options]
      original.call(error, **options)
    end

    described_class.perform_now(import.id)

    expect(import.reload).to have_attributes(status: 'failed', error_code: 'internal')
    error, options = tracked.sole
    expect(error.message).to eq('RuntimeError')
    expect(error.backtrace).to be_present
    expect(options).to eq(account: account)
    text = logged.map { |line| line.is_a?(Exception) ? [line.message, *line.backtrace].join("\n") : line.to_s }.join("\n")
    expect(text).not_to include('segredo')
    expect(text).to include('RuntimeError')
    expect(import.source).not_to be_attached
  end

  it 'keeps the received input when this worker lost the import to a newer attempt' do
    allow(EmailCampaigns::Import::Engine).to receive(:call).and_wrap_original do |original, *args, **kwargs|
      EmailCampaignTemplateImport.where(id: import.id).update_all(attempts: 2, locked_until: 2.minutes.from_now) # rubocop:disable Rails/SkipsModelValidations
      original.call(*args, **kwargs)
    end

    described_class.perform_now(import.id)

    expect(import.reload).to have_attributes(status: 'processing', attempts: 2, result_mjml: nil)
    expect(import.source).to be_attached
  end

  it 'stores what blocks the saving once, when the import finishes' do
    import.source.attach(io: StringIO.new('<p>Olá, {{ campo_que_nao_existe }}</p>'), filename: 'modelo.html', content_type: 'text/html')

    described_class.perform_now(import.id)

    expect(import.reload.blocking.pluck('code')).to eq(['unknown_fields'])
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

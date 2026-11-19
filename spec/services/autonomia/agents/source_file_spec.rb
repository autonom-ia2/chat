require 'rails_helper'

RSpec.describe Autonomia::Agents::SourceFile do
  let(:blob) { instance_double(ActiveStorage::Blob, content_type: content_type) }
  let(:content_type) { 'application/pdf' }

  it 'opens a PDF using a short-lived inline URL' do
    expect(blob).to receive(:url).with(expires_in: 1.minute, disposition: :inline).and_return('temporary-link')

    expect(described_class.new(blob).url).to eq('temporary-link')
  end

  context 'with an office document' do
    let(:content_type) { 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' }

    it 'downloads the original attachment' do
      expect(blob).to receive(:url).with(expires_in: 1.minute, disposition: :attachment)

      described_class.new(blob).url
    end
  end

  context 'with active content' do
    let(:content_type) { 'text/html' }

    it 'does not render the attachment inline' do
      expect(blob).to receive(:url).with(expires_in: 1.minute, disposition: :attachment)

      described_class.new(blob).url
    end
  end
end

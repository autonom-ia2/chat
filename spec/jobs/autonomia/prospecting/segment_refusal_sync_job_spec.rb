require 'rails_helper'

# O job da recusa depois do segmento (#732): roda na fila da Prospecção e entrega a conta e os leads ao sync.
RSpec.describe Autonomia::Prospecting::SegmentRefusalSyncJob do
  let(:account) { create(:account) }

  it 'fica na fila da Prospecção' do
    expect { described_class.perform_later(account.id, [1]) }.to have_enqueued_job(described_class).on_queue('prospecting')
  end

  it 'entrega a conta e os leads ao sync' do
    sync = instance_double(Autonomia::Prospecting::SegmentRefusalSync, perform: nil)
    allow(Autonomia::Prospecting::SegmentRefusalSync).to receive(:new).with(account: account).and_return(sync)

    described_class.perform_now(account.id, [7, 8])

    expect(sync).to have_received(:perform).with([7, 8])
  end

  it 'conta apagada antes do job não faz nada' do
    allow(Autonomia::Prospecting::SegmentRefusalSync).to receive(:new)

    described_class.perform_now(0, [7])

    expect(Autonomia::Prospecting::SegmentRefusalSync).not_to have_received(:new)
  end
end

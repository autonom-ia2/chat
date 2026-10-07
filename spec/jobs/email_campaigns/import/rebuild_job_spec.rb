require 'rails_helper'

# O job de "Refazer para editar" (#1099, entrega D): roda o PartRebuild do clique (importação, trecho e token) e não faz
# nada quando a importação sumiu.
RSpec.describe EmailCampaigns::Import::RebuildJob do
  it 'rebuilds the part of the click' do
    import = create(:account).then { |account| EmailCampaignTemplateImport.create!(account: account, source_kind: 'paste') }
    allow(EmailCampaigns::Import::PartRebuild).to receive(:call)

    described_class.perform_now(import.id, 'trecho-1', 'token')
    described_class.perform_now(0, 'trecho-1', 'token')

    expect(EmailCampaigns::Import::PartRebuild).to have_received(:call).once.with(import, 'trecho-1', 'token')
  end
end

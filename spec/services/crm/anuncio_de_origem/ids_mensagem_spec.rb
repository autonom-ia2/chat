require 'rails_helper'

# #2521: o clique para o Messenger e o Direct é anúncio também nos filtros por campanha (Crm::AnuncioDeOrigem::Ids):
# quem não vê o anúncio de origem não filtra nem escolhe por ele.
RSpec.describe Crm::AnuncioDeOrigem::Ids do
  let(:account) { create(:account) }

  it 'id de toque meta_ctm/meta_ctd é de anúncio; o de divulgação não' do
    { 'meta_ctm' => '120200000000000011', 'meta_ctd' => '120200000000000012', 'campaign_whatsapp' => 'divulgacao-1' }.each do |fonte, id|
      toque = { 'source' => fonte, 'source_id' => id, 'source_type' => fonte.start_with?('meta') ? 'ad' : fonte }
      create(:conversation, account: account,
                            additional_attributes: { 'campaign_touches' => [toque], 'campaign_source_ids' => [id] })
    end

    ids = %w[120200000000000011 120200000000000012 divulgacao-1]
    expect(described_class.de_anuncio(account, ids)).to contain_exactly('120200000000000011', '120200000000000012')
  end
end

require 'rails_helper'

# Leads recusados de um formulário (#2740): lembrados por TTL, presos à linha do formulário como foi lida. Linha
# alterada (destino salvo de novo), outro formulário ou prazo vencido: o lead volta a ser tentado.
RSpec.describe Crm::MetaAds::LeadForms::RefusedLeads do
  let(:account) { create(:account) }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:form) { Crm::MetaAdsLeadForm.create!(account: account, page_id: '104882', form_id: '9001', form_name: 'Orçamento') }

  before { allow(Rails).to receive(:cache).and_return(cache) }

  it 'devolve só os recusados, entre os ids pedidos' do
    described_class.new(form).remember!('L1')

    expect(described_class.new(form.reload).ids(%w[L1 L2])).to eq(['L1'])
  end

  it 'lista vazia: nada recusado' do
    expect(described_class.new(form).ids([])).to eq([])
  end

  it 'outro formulário não herda a recusa' do
    other = Crm::MetaAdsLeadForm.create!(account: account, page_id: '104882', form_id: '7777', form_name: 'Outro')
    described_class.new(form).remember!('L1')

    expect(described_class.new(other).ids(['L1'])).to be_empty
  end

  it 'a linha do formulário mudou: a recusa da versão antiga não vale' do
    stale = described_class.new(form)
    travel(1.second) { form.update!(updated_at: Time.current) }

    stale.remember!('L1')

    expect(described_class.new(form.reload).ids(['L1'])).to be_empty
  end

  it 'vence depois do TTL' do
    described_class.new(form).remember!('L1')

    travel(described_class::TTL + 1.minute) do
      expect(described_class.new(form).ids(['L1'])).to be_empty
    end
  end
end

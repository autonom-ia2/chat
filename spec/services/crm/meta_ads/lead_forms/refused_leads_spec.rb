require 'rails_helper'

# Leads recusados de um formulário (#2740): lembrados por TTL, presos à linha do formulário como foi lida. Linha
# alterada (destino salvo de novo), outro formulário ou prazo vencido: o lead volta a ser tentado. #2804: a recusa do
# destino volta quando o funil ou a etapa mudam; a passageira só fica lembrada depois de algumas tentativas.
RSpec.describe Crm::MetaAds::LeadForms::RefusedLeads do
  let(:account) { create(:account) }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:form) { Crm::MetaAdsLeadForm.create!(account: account, page_id: '104882', form_id: '9001', form_name: 'Orçamento') }

  before { allow(Rails).to receive(:cache).and_return(cache) }

  it 'devolve só os recusados, entre os ids pedidos' do
    described_class.new(form).remember!('L1', :lead)

    expect(described_class.new(form.reload).ids(%w[L1 L2])).to eq(['L1'])
  end

  it 'lista vazia: nada recusado' do
    expect(described_class.new(form).ids([])).to eq([])
  end

  it 'outro formulário não herda a recusa' do
    other = Crm::MetaAdsLeadForm.create!(account: account, page_id: '104882', form_id: '7777', form_name: 'Outro')
    described_class.new(form).remember!('L1', :lead)

    expect(described_class.new(other).ids(['L1'])).to be_empty
  end

  it 'a linha do formulário mudou: a recusa da versão antiga não vale' do
    stale = described_class.new(form)
    travel(1.second) { form.update!(updated_at: Time.current) }

    stale.remember!('L1', :lead)

    expect(described_class.new(form.reload).ids(['L1'])).to be_empty
  end

  it 'vence depois do TTL' do
    described_class.new(form).remember!('L1', :lead)

    travel(described_class::TTL + 1.minute) do
      expect(described_class.new(form).ids(['L1'])).to be_empty
    end
  end

  # #2804: a recusa do destino (funil ou etapa que o card não aceita) volta quando alguém conserta o funil ou a etapa,
  # mesmo sem salvar o destino de novo. A do próprio lead, não: consertar o funil não muda o dado dele.
  describe 'com destino' do
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
    let(:pipeline) { pipeline_and_stage.first }
    let(:stage) { pipeline_and_stage.last }
    let(:form) do
      Crm::MetaAdsLeadForm.create!(account: account, page_id: '104882', form_id: '9001', form_name: 'Orçamento',
                                   pipeline: pipeline, stage: stage)
    end

    def reler = described_class.new(Crm::MetaAdsLeadForm.find(form.id))

    it 'funil mudou: a recusa do destino não vale mais' do
      described_class.new(form).remember!('L1', :destination)
      travel(1.second) { pipeline.update!(name: 'Vendas corrigido') }

      expect(reler.ids(['L1'])).to be_empty
    end

    it 'etapa mudou: a recusa do destino não vale mais' do
      described_class.new(form).remember!('L1', :destination)
      travel(1.second) { stage.update!(name: 'Qualificar') }

      expect(reler.ids(['L1'])).to be_empty
    end

    it 'funil mudou: a recusa do próprio lead continua' do
      described_class.new(form).remember!('L1', :lead)
      travel(1.second) { pipeline.update!(name: 'Vendas corrigido') }

      expect(reler.ids(['L1'])).to eq(['L1'])
    end

    it 'nada mudou: a recusa do destino continua' do
      described_class.new(form).remember!('L1', :destination)

      expect(reler.ids(['L1'])).to eq(['L1'])
    end
  end

  # #2804: erro passageiro (corrida no banco) volta na rodada seguinte, mas não para sempre: depois de
  # TRANSIENT_ATTEMPTS seguidas, fica lembrado como recusa do lead, e o laço da #2740 não volta.
  describe 'recusa passageira' do
    it 'não fica lembrada nas primeiras tentativas' do
      (described_class::TRANSIENT_ATTEMPTS - 1).times { described_class.new(form).remember!('L1', :transient) }

      expect(described_class.new(form).ids(['L1'])).to be_empty
    end

    it 'na última tentativa, fica lembrada até o TTL' do
      described_class::TRANSIENT_ATTEMPTS.times { described_class.new(form).remember!('L1', :transient) }

      expect(described_class.new(form).ids(['L1'])).to eq(['L1'])
      travel(described_class::TTL + 1.minute) do
        expect(described_class.new(form).ids(['L1'])).to be_empty
      end
    end

    # O lead ainda está na janela de 48 h depois do prazo da recusa: uma falha a mais já a grava de novo.
    it 'vencido o prazo da recusa, uma falha a mais já a grava de novo' do
      described_class::TRANSIENT_ATTEMPTS.times { described_class.new(form).remember!('L1', :transient) }

      travel(described_class::TTL + 1.minute) do
        described_class.new(form).remember!('L1', :transient)

        expect(described_class.new(form).ids(['L1'])).to eq(['L1'])
      end
    end

    it 'salvar o destino de novo não zera a conta' do
      (described_class::TRANSIENT_ATTEMPTS - 1).times { described_class.new(form).remember!('L1', :transient) }
      travel(1.second) { form.update!(updated_at: Time.current) }

      described_class.new(form.reload).remember!('L1', :transient)

      expect(described_class.new(form).ids(['L1'])).to eq(['L1'])
    end

    it 'cada lead conta as suas tentativas' do
      (described_class::TRANSIENT_ATTEMPTS - 1).times { described_class.new(form).remember!('L1', :transient) }
      described_class.new(form).remember!('L2', :transient)

      expect(described_class.new(form).ids(%w[L1 L2])).to be_empty
    end
  end
end

require 'rails_helper'

# Item 4 da #2740 (#2804): funil arquivado e reativado sem salvar o destino do formulário de novo. Com o funil fechado o
# webhook não trouxe ninguém; reativar vale como salvar o destino naquela hora: o marco da reconciliação
# (destination_set_at) nasce de novo, e ela não relê quem preencheu com o funil fechado.
RSpec.describe Crm::Pipeline do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:outro) { create_crm_pipeline(account: account, user: admin, name: 'Outro') }
  let(:antes) { 3.days.ago.change(usec: 0) }

  def formulario(form_id, (funil, etapa))
    Crm::MetaAdsLeadForm.create!(account: account, page_id: '104882', form_id: form_id, form_name: 'Orçamento',
                                 pipeline: funil, stage: etapa, destination_set_at: antes)
  end

  it 'reativado: o marco dos formulários dele nasce na reativação; os de outro funil ficam' do
    deste = formulario('9001', pipeline_and_stage)
    daquele = formulario('9002', outro)
    pipeline.archived!

    freeze_time do
      pipeline.active!

      expect(deste.reload.destination_set_at).to eq(Time.current)
    end
    expect(daquele.reload.destination_set_at).to eq(antes)
  end

  it 'formulário sem etapa (etapa apagada) não ganha marco' do
    sem_etapa = formulario('9003', [pipeline, nil])
    pipeline.archived!

    pipeline.active!

    expect(sem_etapa.reload.destination_set_at).to eq(antes)
  end

  it 'arquivar, ou mudar outra coisa no funil, não mexe no marco' do
    deste = formulario('9001', pipeline_and_stage)

    pipeline.archived!
    pipeline.update!(name: 'Vendas 2')

    expect(deste.reload.destination_set_at).to eq(antes)
  end
end

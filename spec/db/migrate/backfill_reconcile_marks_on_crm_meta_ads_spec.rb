require 'rails_helper'
require Rails.root.join('db/migrate/20261108880000_backfill_reconcile_marks_on_crm_meta_ads.rb')

# #2740: o formulário com destino e a Página recebendo de antes do #2285 ganham o momento do deploy como marco de início.
# A reconciliação passa a reler esses formulários, mas só o que chegar depois do deploy: nenhum lead antigo entra.
RSpec.describe BackfillReconcileMarksOnCrmMetaAds do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:antes) { Time.utc(2026, 11, 1, 12) }

  def formulario(form_id, destino: true, marco: nil)
    pipeline, stage = destino ? pipeline_and_stage : [nil, nil]
    Crm::MetaAdsLeadForm.create!(account: account, page_id: '104882', form_id: form_id, pipeline: pipeline, stage: stage,
                                 destination_set_at: marco)
  end

  def pagina(page_id, recebendo: true, marco: nil)
    Crm::MetaAdsPage.create!(account: account, page_id: page_id, leadgen_receiving: recebendo, leadgen_receiving_since: marco)
  end

  def preencher
    described_class.new.up
  end

  it 'grava o momento do deploy no formulário com destino e na Página recebendo que estavam sem marco', :aggregate_failures do
    form = formulario('9001')
    page = pagina('104882')

    freeze_time do
      preencher

      expect(form.reload.destination_set_at).to eq(Time.current)
      expect(page.reload.leadgen_receiving_since).to eq(Time.current)
    end
    expect(Crm::MetaAdsLeadForm.reconcilable).to contain_exactly(form)
  end

  it 'não toca marco que já existe, formulário sem destino nem Página parada; rodar de novo não muda nada', :aggregate_failures do
    com_marco = formulario('9001', marco: antes)
    sem_destino = formulario('9002', destino: false)
    pagina_com_marco = pagina('104882', marco: antes)
    parada = pagina('104883', recebendo: false)

    2.times { preencher }

    expect(com_marco.reload.destination_set_at).to eq(antes)
    expect(sem_destino.reload.destination_set_at).to be_nil
    expect(pagina_com_marco.reload.leadgen_receiving_since).to eq(antes)
    expect(parada.reload.leadgen_receiving_since).to be_nil
  end

  it 'só mexe nas duas colunas do marco', :aggregate_failures do
    form = formulario('9001')
    page = pagina('104882')
    form_antes = form.attributes.except('destination_set_at')
    page_antes = page.attributes.except('leadgen_receiving_since')

    preencher

    expect(form.reload.attributes.except('destination_set_at')).to eq(form_antes)
    expect(page.reload.attributes.except('leadgen_receiving_since')).to eq(page_antes)
  end
end

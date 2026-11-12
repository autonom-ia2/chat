require 'rails_helper'

# #2501: o funil sem uma etapa dele no pedido da API cai na etapa de entrada do funil, e não num erro.
RSpec.describe Crm::Cards::EtapaDeEntrada do
  let(:account_and_admin) { create_account_and_user }
  let(:account) { account_and_admin.first }
  let(:admin) { account_and_admin.last }
  let(:funil) { account.crm_pipelines.create!(name: 'Pós-venda', created_by: admin, status: :active) }

  def para(pipeline_id:, stage_id: nil)
    described_class.para(account: account, pipeline_id: pipeline_id, stage_id: stage_id)
  end

  it 'não decide nada sem funil no pedido ou com uma etapa do funil' do
    etapa = create_crm_stage(account: account, pipeline: funil, name: 'Entrada', position: 0)

    expect(para(pipeline_id: nil, stage_id: etapa.id)).to be_nil
    expect(para(pipeline_id: funil.id.to_s, stage_id: etapa.id)).to be_nil
  end

  it 'escolhe a primeira etapa pela posição, com o motivo' do
    create_crm_stage(account: account, pipeline: funil, name: 'Depois', position: 4)
    entrada = create_crm_stage(account: account, pipeline: funil, name: 'Entrada', position: 1)
    _outro_funil, etapa_de_fora = create_crm_pipeline(account: account, user: admin)

    expect(para(pipeline_id: funil.id).to_a).to eq([entrada, described_class::SEM_ETAPA])
    expect(para(pipeline_id: funil.id, stage_id: etapa_de_fora.id).to_a).to eq([entrada, described_class::ETAPA_DE_OUTRO_FUNIL])
    expect(para(pipeline_id: funil.id, stage_id: 0).to_a).to eq([entrada, described_class::ETAPA_DE_OUTRO_FUNIL])
  end

  it 'recusa o funil sem etapa nenhuma com o código de sempre' do
    expect { para(pipeline_id: funil.id) }.to raise_error(described_class::FunilSemEtapa, 'crm.upsert_stage_of_pipeline_required')
  end
end

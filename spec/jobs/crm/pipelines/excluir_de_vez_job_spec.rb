require 'rails_helper'

# Excluir de vez um funil com cards (#2096): o job confere de novo e, quando algo barra, não apaga nada.
RSpec.describe Crm::Pipelines::ExcluirDeVezJob do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:destino) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:contact) { account.contacts.create!(name: 'Cliente', phone_number: '+5511999990004') }
  let!(:card) { account.crm_cards.create!(pipeline: pipeline, stage: pipeline_and_stage.last, contact: contact, title: 'Pedido') }

  before { pipeline.archived! }

  it 'move e apaga o funil' do
    described_class.perform_now(pipeline.id, admin.id, 'move', destino.last.id)

    expect(Crm::Pipeline.exists?(pipeline.id)).to be(false)
    expect(card.reload.pipeline_id).to eq(destino.first.id)
  end

  it 'não faz nada quando o destino foi arquivado enquanto esperava' do
    destino.first.archived!

    described_class.perform_now(pipeline.id, admin.id, 'move', destino.last.id)

    expect([pipeline.reload.present?, card.reload.pipeline_id]).to eq([true, pipeline.id])
  end

  it 'não faz nada quando um card não pode ir para o destino' do
    dono = create(:user, account: account, role: :agent)
    card.update!(owner: dono)
    AccountUser.find_by!(account: account, user: dono).destroy!

    described_class.perform_now(pipeline.id, admin.id, 'move', destino.last.id)

    expect([pipeline.reload.present?, card.reload.pipeline_id]).to eq([true, pipeline.id])
  end

  it 'não apaga nada quando a reunião futura não cancela' do
    create_reuniao(account: account, card: card, user: admin, contact: contact, starts_at: 2.days.from_now)
    servico = instance_double(Crm::Meetings::CancelService)
    allow(servico).to receive(:perform).and_raise(Net::OpenTimeout)
    allow(Crm::Meetings::CancelService).to receive(:new).and_return(servico)

    described_class.perform_now(pipeline.id, admin.id, 'delete')

    expect([Crm::Pipeline.exists?(pipeline.id), Crm::Card.exists?(card.id)]).to eq([true, true])
  end
end

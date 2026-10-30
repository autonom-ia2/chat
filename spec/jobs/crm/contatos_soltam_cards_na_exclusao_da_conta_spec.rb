require 'rails_helper'

# #2096: apagar a conta não cancela reunião de cliente nem anonimiza card um a um; os contatos só soltam os cards.
RSpec.describe Crm::ContatosSoltamCardsNaExclusaoDaConta do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:contact) { account.contacts.create!(name: 'Cliente', phone_number: '+5511999990077') }
  let(:card) do
    pipeline, stage = pipeline_and_stage
    account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: 'Pedido', status: :open)
  end

  # Com a flag, o contato excluído fora daqui anonimiza os cards e cancela as reuniões (ContactCrmCards).
  before { account.enable_features!(:crm_arquivados) }

  it 'na exclusão da conta, o contato sai sem chamar o calendário e só solta o card' do
    create_reuniao(account: account, card: card, user: admin, contact: contact, starts_at: 2.days.from_now)
    allow(Crm::Meetings::CancelarFuturas).to receive(:new).and_call_original

    Crm::Cards::Anonimizador.durante_exclusao_da_conta { contact.destroy! }

    expect(Crm::Meetings::CancelarFuturas).not_to have_received(:new)
    expect(card.reload.contact_id).to be_nil
    expect(card.title).to eq('Pedido')
    expect(Crm::Cards::Anonimizador.conta_saindo?).to be(false)
  end

  it 'o DeleteObjectJob da conta liga esse modo; o de outro objeto não' do
    allow(Crm::Cards::Anonimizador).to receive(:durante_exclusao_da_conta)

    DeleteObjectJob.perform_now(account)
    expect(Crm::Cards::Anonimizador).to have_received(:durante_exclusao_da_conta).once

    DeleteObjectJob.perform_now(contact)
    expect(Crm::Cards::Anonimizador).to have_received(:durante_exclusao_da_conta).once
  end

  it 'fora da exclusão da conta, o contato excluído continua anonimizando os cards' do
    card

    DeleteObjectJob.perform_now(contact)

    expect(card.reload.contact_id).to be_nil
    expect(card.metadata).to have_key(Crm::Cards::Anonimizador::MARCA)
  end
end

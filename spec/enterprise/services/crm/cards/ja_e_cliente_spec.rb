require 'rails_helper'

# #2710 no EE: a função sem `crm_view` não vê card do CRM (Enterprise::Crm::CardPolicy#show?), então não recebe o selo
# "Já é cliente", nem no quadro nem no card aberto e no tempo real.
RSpec.describe Crm::Cards::JaECliente do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:pos_venda) { create_crm_pipeline(account: account, user: admin, name: 'Pós-venda') }
  let(:contact) do
    account.contacts.create!(name: 'Ana Costa', phone_number: "+55119#{rand(10_000_000..99_999_999)}")
           .tap { |contato| contato.update!(contact_type: :customer, customer_since: Time.zone.parse('2026-11-03 10:00')) }
  end

  def com_funcao(permissions)
    user = create(:user, account: account, role: :agent)
    AccountUser.find_by(account: account, user: user).tap do |account_user|
      account_user.update!(custom_role: create(:custom_role, account: account, permissions: permissions))
    end
  end

  def selos(account_user, inbox)
    ganho_e_agenda(inbox)
    agenda = account.crm_cards.find_by!(source: 'public_link')
    described_class.new(user: account_user.user, account: account, account_user: account_user).para([agenda])
  end

  def ganho_e_agenda(inbox)
    pipeline, stage = pos_venda
    ganho = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Plano mensal', inbox: inbox, contact: contact)
    ganho.update_columns(status: Crm::Card.statuses[:won], closed_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    pipeline, stage = vendas
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Ana Costa - Agenda', inbox: inbox, contact: contact,
                              source: 'public_link')
  end

  it 'a função sem crm_view não recebe o selo, mesmo vendo a base de contatos e a caixa' do
    sem_crm = com_funcao(%w[contact_view crm_manage_cards])
    inbox = create_crm_inbox(account: account, members: [sem_crm.user])

    expect(selos(sem_crm, inbox)).to eq({})
  end

  it 'a função com crm_view e contact_view recebe o selo' do
    com_crm = com_funcao(%w[crm_view contact_view])
    inbox = create_crm_inbox(account: account, members: [com_crm.user])

    expect(selos(com_crm, inbox).values.first).to include(:card_id, :desde)
  end

  it 'no card aberto e no tempo real, a função sem crm_view também não recebe' do
    sem_crm = com_funcao(%w[contact_view crm_manage_cards])
    agenda = ganho_e_agenda(create_crm_inbox(account: account, members: [sem_crm.user]))

    expect(Crm::Cards::JaEClienteDoCard.new(agenda).para(user: sem_crm.user, account_user: sem_crm)).to be_nil
  end
end

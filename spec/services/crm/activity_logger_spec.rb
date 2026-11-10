require 'rails_helper'

RSpec.describe Crm::ActivityLogger do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:funil) { create_crm_pipeline(account: account, user: admin) }
  let(:card) { account.crm_cards.create!(pipeline: funil.first, stage: funil.last, title: 'Pedido') }

  it 'a ação de um super admin fica registrada como de pessoa, com o id dele' do
    super_admin = create(:super_admin)

    atividade = described_class.new(card: card, actor: super_admin, event_type: 'archive').perform

    expect(atividade.reload).to have_attributes(actor_type: 'user', actor_id: super_admin.id)
  end

  it 'sem ator, a ação é do sistema' do
    atividade = described_class.new(card: card, actor: nil, event_type: 'archive').perform

    expect(atividade.reload).to have_attributes(actor_type: 'system', actor_id: nil)
  end
end

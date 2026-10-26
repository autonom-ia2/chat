require 'rails_helper'

# #2216: reabrir sem o rodízio só vale para essa troca de status; o resto da atribuição automática segue igual.
RSpec.describe Conversations::ReabrirSemRodizio do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: true) }
  let(:agent) { create(:user, account: account, role: :agent, auto_offline: false) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox, status: :resolved, assignee: nil) }

  before { create(:inbox_member, user: agent, inbox: inbox) }

  it 'o open! de sempre ainda chama o rodízio' do
    conversa.open!

    expect(conversa.reload.assignee).to eq(agent)
  end

  it 'reabre sem chamar o rodízio' do
    conversa.reabrir_sem_rodizio!

    expect(conversa.reload).to be_open
    expect(conversa.assignee).to be_nil
  end

  it 'a próxima reabertura da mesma conversa volta a chamar o rodízio' do
    conversa.reabrir_sem_rodizio!
    conversa.resolved!
    conversa.open!

    expect(conversa.reload.assignee).to eq(agent)
  end
end

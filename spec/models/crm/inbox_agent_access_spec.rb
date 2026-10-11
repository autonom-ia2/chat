require 'rails_helper'

RSpec.describe Crm::InboxAgentAccess do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create_crm_agent(account: account).first }
  let(:inbox) { create_crm_inbox(account: account, members: [agent]) }

  it 'só libera tudo quando todos os funis, triagem e todas as conversas' do
    expect(described_class.new(all_pipelines: true, triage: true, only_own: false)).not_to be_restricts
    expect(described_class.new(all_pipelines: false, triage: true, only_own: false)).to be_restricts
    expect(described_class.new(all_pipelines: true, triage: false, only_own: false)).to be_restricts
    expect(described_class.new(all_pipelines: true, triage: true, only_own: true)).to be_restricts
  end

  it 'recusa caixa de outra conta' do
    other_inbox = create_crm_inbox(account: create(:account))

    expect(described_class.new(account: account, inbox: other_inbox, user: agent)).not_to be_valid
  end

  it 'recusa pessoa que não é da conta' do
    stranger = create(:user)

    expect(described_class.new(account: account, inbox: inbox, user: stranger)).not_to be_valid
  end

  it 'recusa funil de outra conta' do
    access = described_class.create!(account: account, inbox: inbox, user: agent, all_pipelines: false)
    other = create(:account)
    foreign_pipeline = create_crm_pipeline(account: other, user: create(:user, account: other, role: :administrator)).first

    expect(access.agent_pipelines.new(account: account, pipeline: foreign_pipeline)).not_to be_valid
  end
end

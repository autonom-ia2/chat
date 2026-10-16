require 'rails_helper'

# #1619: prepend em Sla::ScheduleResolver. Ligada, só o calendário do responsável; desligada, responsável > caixa.
RSpec.describe Autonomia::HorarioUnicoCaixa::ScheduleResolver do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: agent) }
  let!(:inbox_schedule) { create(:crm_service_schedule, account: account, owner: inbox) }

  def resolve
    Sla::ScheduleResolver.for_conversation(conversation)
  end

  it 'is prepended to Sla::ScheduleResolver' do
    expect(Sla::ScheduleResolver.singleton_class.ancestors).to include(described_class)
  end

  context 'when the flag is off' do
    it 'resolves the inbox calendar as before' do
      expect(resolve).to eq(inbox_schedule)
    end

    it 'prefers a usable agent calendar' do
      agent_schedule = create(:crm_service_schedule, account: account, owner: agent)

      expect(resolve).to eq(agent_schedule)
    end
  end

  context 'when the flag is on' do
    before { account.enable_features!(Autonomia::HorarioUnicoCaixa::FEATURE) }

    it 'returns a usable agent calendar' do
      agent_schedule = create(:crm_service_schedule, account: account, owner: agent)

      expect(resolve).to eq(agent_schedule)
    end

    it 'never returns the inbox calendar' do
      expect(resolve).to be_nil
    end

    it 'returns nil when the agent calendar is disabled' do
      create(:crm_service_schedule, account: account, owner: agent, enabled: false)

      expect(resolve).to be_nil
    end

    it 'returns nil without an assignee' do
      conversation.update!(assignee: nil)

      expect(resolve).to be_nil
    end

    it 'ignores an agent calendar from another account' do
      create(:crm_service_schedule, account: create(:account), owner: agent)

      expect(resolve).to be_nil
    end
  end
end

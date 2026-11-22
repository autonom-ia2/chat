require 'rails_helper'

# Upgrade 4.20.1 (#3120): o upstream #16584 tira o robô sempre que a conversa vira "Aberta". O fork recusa: a conversa
# do robô fica aberta e no nome dele até uma pessoa entrar (#1377). Este spec trava as duas pontas no modelo, sem passar
# pela passagem (ConversationBotHandoff), que tem cobertura própria em conversation_bot_assignment_spec.rb.
RSpec.describe 'Robô na conversa ao abrir' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:bot) { create(:agent_bot, account: account) }

  before { create(:inbox_member, inbox: inbox, user: agent) }

  %i[resolved pending snoozed].each do |status|
    it "mantém o robô quando a conversa #{status} passa a aberta sem pessoa" do
      conversation = create(:conversation, account: account, inbox: inbox, status: status)
      conversation.update!(ai_assignee: bot)

      conversation.update!(status: :open)

      expect(conversation.reload).to have_attributes(status: 'open', assignee_id: nil, ai_assignee: bot)
    end
  end

  it 'tira o robô quando uma pessoa é atribuída' do
    conversation = create(:conversation, account: account, inbox: inbox, status: :open)
    conversation.update!(ai_assignee: bot)

    conversation.update!(assignee: agent)

    expect(conversation.reload).to have_attributes(assignee: agent, ai_assignee: nil)
  end
end

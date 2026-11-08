require 'rails_helper'

# Caixa com uma linha de robô inativa e outra ativa (#2298, sem índice único por inbox_id): o Ruby fica com a ativa,
# como o SQL da Lista ("qualquer ativa"), lido direto ou com preload. Sem duplicata, nada muda.
RSpec.describe Inbox do
  let(:account) { create(:account) }
  let(:inbox) { create_crm_inbox(account: account) }
  let(:inactive_bot) { create(:agent_bot, account: account, name: 'Robô desligado') }
  let(:active_bot) { create(:agent_bot, account: account, name: 'Robô ligado') }

  before do
    AgentBotInbox.create!(inbox: inbox, agent_bot: inactive_bot, status: :inactive)
    AgentBotInbox.create!(inbox: inbox, agent_bot: active_bot, status: :active)
  end

  it 'prefere a linha ativa, lida direto' do
    fresh = described_class.find(inbox.id)

    expect(fresh.agent_bot_inbox).to be_active
    expect(fresh.agent_bot).to eq(active_bot)
    expect(fresh).to be_active_bot
  end

  it 'prefere a linha ativa com preload' do
    preloaded = described_class.where(id: inbox.id).preload({ agent_bot_inbox: :agent_bot }, :agent_bot).first

    expect(preloaded.agent_bot_inbox).to be_active
    expect(preloaded.agent_bot_inbox.agent_bot).to eq(active_bot)
    expect(preloaded.agent_bot).to eq(active_bot)
  end

  it 'mostra o robô ativo como quem cuida do card da caixa' do
    pipeline, stage = create_crm_pipeline(account: account, user: create(:user, account: account, role: :administrator))
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Card da caixa', inbox: inbox)

    expect(Crm::Card.find(card.id).current_responsible).to eq(type: 'bot', id: active_bot.id, name: 'Robô ligado')
  end
end

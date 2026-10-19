require 'rails_helper'

RSpec.describe Crm::Reports::Summary do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create_crm_inbox(account: account, members: [user]) }
  let(:sale) { create_crm_pipeline(account: account, user: user) }
  let(:service) do
    pipeline = account.crm_pipelines.create!(name: 'Sinistros', created_by: user, status: :active, counts_as_sale: false)
    [pipeline, account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'Aberto', position: 0)]
  end

  def summary_for(pipeline)
    described_class.new(account: account, params: { pipeline_id: pipeline.id }).perform
  end

  def new_conversation(contact = create(:contact, account: account))
    create_crm_conversation(account: account, inbox: inbox, contact: contact)
  end

  def create_card(pipeline_and_stage, conversation: nil, status: :open, value_cents: 0)
    pipeline, stage = pipeline_and_stage
    card = account.crm_cards.create!(
      pipeline: pipeline, stage: stage, primary_conversation: conversation, contact: conversation&.contact,
      title: "Assunto #{SecureRandom.hex(3)}", currency: 'BRL', value_cents: value_cents
    )
    card.update!(status: status) unless status == :open
    card
  end

  describe 'win rate' do
    it 'counts two real sales in the same conversation as two' do
      conversation = new_conversation
      create_card(sale, conversation: conversation, status: :won, value_cents: 10_000)
      create_card(sale, conversation: conversation, status: :won, value_cents: 5_000)
      create_card(sale, conversation: conversation, status: :lost, value_cents: 5_000)

      result = summary_for(sale.first)

      expect(result).to include(counts_as_sale: true, won_count: 2, lost_count: 1, win_rate: 0.6667, win_rate_by_value: 0.75)
      expect(result[:won_value_by_currency]).to eq([{ currency: 'BRL', value_cents: 15_000 }])
    end

    it 'never counts a service funnel as a sale, even a card won before the funnel stopped counting as sale' do
      conversation = new_conversation
      create_card(sale, conversation: conversation, status: :won, value_cents: 9_000)
      sale.first.update!(counts_as_sale: false)
      create_card(sale, conversation: conversation, status: :resolved)
      create_card(sale, conversation: conversation, status: :cancelled)

      result = summary_for(sale.first)

      expect(result).to include(
        counts_as_sale: false, won_count: 0, lost_count: 0, win_rate: nil, win_rate_by_value: nil,
        won_value_by_currency: [], lost_value_by_currency: [], resolved_count: 1, cancelled_count: 1, goal: nil
      )
    end

    it 'ignores resolved and cancelled cards left in a sale funnel' do
      create_card(service, status: :resolved)
      service.first.update!(counts_as_sale: true)
      create_card(service, status: :won)

      expect(summary_for(service.first)).to include(won_count: 1, lost_count: 0, win_rate: 1.0, resolved_count: 0)
    end
  end

  # #1876: o mês da meta é o da conta, não o do servidor (UTC). 31/10 às 22h em São Paulo é 01/11 01h em UTC.
  describe 'goal month in the account timezone' do
    def won_at(time, value_cents)
      card = create_card(sale, status: :won, value_cents: value_cents)
      card.update_columns(closed_at: time) # rubocop:disable Rails/SkipsModelValidations
      card
    end

    it 'counts a sale closed on 31/10 at 22h (São Paulo) in October, and one closed on 30/09 at 23h out of it' do
      account.update!(reporting_timezone: 'America/Sao_Paulo')
      sale.first.update!(metadata: { 'goals' => { 'monthly_target_cents' => 100_000, 'currency' => 'BRL' } })
      won_at(Time.utc(2026, 11, 1, 1, 0), 30_000)
      won_at(Time.utc(2026, 10, 1, 2, 0), 50_000)
      won_at(Time.utc(2026, 10, 15, 12, 0), 7_000)

      goal = travel_to(Time.utc(2026, 11, 1, 2, 0)) { summary_for(sale.first)[:goal] }

      expect(goal).to include(month_label: '10/2026', achieved_cents: 37_000)
    end
  end

  describe 'people, conversations and cards' do
    it 'counts one person, one conversation and three cards for a conversation with three open cards' do
      conversation = new_conversation
      3.times { create_card(sale, conversation: conversation) }

      expect(summary_for(sale.first)).to include(open_count: 3, open_conversations_count: 1, open_people_count: 1)
    end

    it 'counts conversations linked to an open card and people with no conversation' do
      contact = create(:contact, account: account)
      first = new_conversation(contact)
      second = new_conversation(contact)
      card = create_card(sale, conversation: first)
      Crm::CardConversation.create!(account: account, card: card, conversation: second)
      pipeline, stage = sale
      account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: create(:contact, account: account), title: 'Sem conversa', currency: 'BRL')
      create_card(sale, conversation: new_conversation, status: :won)

      expect(summary_for(pipeline)).to include(open_count: 2, open_conversations_count: 2, open_people_count: 2)
    end
  end
end

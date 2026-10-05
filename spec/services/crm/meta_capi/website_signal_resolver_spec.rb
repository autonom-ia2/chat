require 'rails_helper'

# Sinais do navegador para o modo site do funil de volta à Meta (#1011, seção 6).
RSpec.describe Crm::MetaCapi::WebsiteSignalResolver do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create_crm_inbox(account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:linked_conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:other_conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:pipeline) { account.crm_pipelines.create!(name: 'P', created_by: user, status: :active) }
  let(:stage) { account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'S', position: 0) }
  let(:card) do
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Card', currency: 'BRL', primary_conversation: conversation)
  end
  let(:tracked_link) do
    create(:ctwa_tracked_link, account: account, usage: 'website', allowed_origins: ['https://placement.com.br'])
  end

  let(:signals) do
    { 'fbc' => 'fb.1.1759650000000.IwAR123', 'fbp' => 'fb.1.1759650000000.123456789',
      'client_ip_address' => '200.1.2.3', 'client_user_agent' => 'Mozilla/5.0 iPhone' }
  end

  def click(conversation:, meta_signals:, created_at: Time.current)
    create(:ctwa_tracked_link_click, account: account, tracked_link: tracked_link, conversation: conversation,
                                     meta_signals: meta_signals, created_at: created_at)
  end

  it 'returns the signals of the click tied to the card conversation' do
    click(conversation: conversation, meta_signals: signals)

    expect(described_class.resolve(card)).to eq(signals)
  end

  it 'prefers the most recent click among the primary and linked conversations' do
    Crm::CardConversation.create!(account: account, card: card, conversation: linked_conversation)
    click(conversation: conversation, meta_signals: signals, created_at: 2.hours.ago)
    newer = signals.merge('fbc' => 'fb.1.1759660000000.NEWER')
    click(conversation: linked_conversation, meta_signals: newer, created_at: 10.minutes.ago)

    expect(described_class.resolve(card)).to eq(newer)
  end

  it 'ignores clicks of conversations that are not on the card' do
    click(conversation: other_conversation, meta_signals: signals)

    expect(described_class.resolve(card)).to eq({})
  end

  it 'ignores clicks that were never tied to a conversation' do
    click(conversation: nil, meta_signals: signals)

    expect(described_class.resolve(card)).to eq({})
  end

  it 'returns empty when the visitor gave no marketing consent (no signals stored)' do
    click(conversation: conversation, meta_signals: {})

    expect(described_class.resolve(card)).to eq({})
  end

  it 'skips a newer click without consent and uses the older one that has signals' do
    click(conversation: conversation, meta_signals: signals, created_at: 1.hour.ago)
    click(conversation: conversation, meta_signals: {}, created_at: 1.minute.ago)

    expect(described_class.resolve(card)).to eq(signals)
  end

  it 'keeps only the known Meta keys with string values' do
    click(conversation: conversation, meta_signals: { 'fbc' => 'fb.1.1.abc', 'fbp' => '', 'extra' => 'x' })

    expect(described_class.resolve(card)).to eq('fbc' => 'fb.1.1.abc')
  end

  it 'never reads clicks from another account' do
    other_account = create(:account)
    foreign_link = create(:ctwa_tracked_link, account: other_account)
    create(:ctwa_tracked_link_click, account: other_account, tracked_link: foreign_link, conversation: conversation,
                                     meta_signals: signals)

    expect(described_class.resolve(card)).to eq({})
  end

  it 'returns empty for a card without conversations' do
    card.update!(primary_conversation: nil)

    expect(described_class.resolve(card)).to eq({})
  end
end

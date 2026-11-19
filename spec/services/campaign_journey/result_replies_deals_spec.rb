require 'rails_helper'

# #3063 — o resultado da campanha em R$: o valor dos cards que fecharam venda com a marca da campanha (ganhos, ou
# resolvidos na renovação com a apólice nova já na carteira); no card de renovação cuja apólice nova chegou, o prêmio dela.
RSpec.describe CampaignJourney::ResultReplies, '#deals', :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:reply_inbox) { create_crm_inbox(account: account, members: [admin]) }
  let(:whatsapp_inbox) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox }
  let(:campaign) { create(:campaign, account: account, inbox: whatsapp_inbox, title: 'Renovação auto', campaign_type: :one_off) }
  let(:source_id) { CampaignJourney::CampaignMarks.source_id_for(campaign) }
  let(:sale) { create_crm_pipeline(account: account, user: admin) }
  let(:service) do
    pipeline = account.crm_pipelines.create!(name: 'Renovações', created_by: admin, status: :active, counts_as_sale: false)
    stage = account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'A renovar', position: 0)
    [pipeline, stage]
  end

  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run }
  end

  def marked_conversation(name)
    contact = account.contacts.create!(name: name, phone_number: "+55119#{rand(10_000_000..99_999_999)}")
    conversation = create_crm_conversation(account: account, inbox: reply_inbox, contact: contact)
    CampaignJourney::CampaignMarks.mark!(conversation, campaign)
    conversation
  end

  def card(name, status:, value_cents: 0, currency: 'BRL', pipeline_and_stage: sale)
    conversation = marked_conversation(name)
    pipeline, stage = pipeline_and_stage
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: name, conversation_id: conversation.id,
                              contact: conversation.contact, status: status, value_cents: value_cents, currency: currency)
  end

  def renewal(card, premium:, cancelled: false)
    previous = create(:carteira_apolice, account: account, contact: card.contact, crm_card_id: card.id, valor_centavos: 90_000)
    create(:carteira_apolice, account: account, contact: card.contact, apolice_anterior: previous, valor_centavos: premium,
                              cancelado_em: (Time.current if cancelled))
  end

  it 'sums the won cards and the renewals with the new policy in, with the premium of the new policy' do
    card('Ana', status: :won, value_cents: 50_000)
    renewed = card('Bia', status: :resolved, value_cents: 10_000, pipeline_and_stage: service)
    renewal(renewed, premium: 120_000)
    card('Caio', status: :lost, value_cents: 99_900)
    card('Davi', status: :open, value_cents: 77_700)
    card('Eva', status: :won, value_cents: 5_000, currency: ' usd ')
    card('Fábio', status: :resolved, value_cents: 30_000, pipeline_and_stage: service)

    deals = described_class.new(account, source_id).deals(with_value: true)

    expect(deals).to eq(cards: 6, won: 3, won_value: [{ currency: 'BRL', cents: 170_000 }, { currency: 'USD', cents: 5_000 }])
  end

  it 'leaves out the funnels the reader does not see' do
    card('Ana', status: :won, value_cents: 50_000)
    renewal(card('Bia', status: :resolved, value_cents: 0, pipeline_and_stage: service), premium: 120_000)

    deals = described_class.new(account, source_id).deals(with_value: true, pipeline_ids: [sale.first.id])

    expect(deals).to eq(cards: 1, won: 1, won_value: [{ currency: 'BRL', cents: 50_000 }])
  end

  it 'keeps the card value when the new policy was cancelled or has no premium' do
    cancelled = card('Ana', status: :won, value_cents: 30_000)
    renewal(cancelled, premium: 200_000, cancelled: true)
    without_premium = card('Bia', status: :won, value_cents: 20_000)
    renewal(without_premium, premium: nil)

    expect(described_class.new(account, source_id).deals(with_value: true)[:won_value]).to eq([{ currency: 'BRL', cents: 50_000 }])
  end

  it 'counts a card archived after being won' do
    archived = card('Ana', status: :won, value_cents: 40_000)
    archived.update!(status: :archived)

    expect(described_class.new(account, source_id).deals(with_value: true)).to include(won: 1, won_value: [{ currency: 'BRL', cents: 40_000 }])
  end

  it 'leaves the value out for who does not see sales values' do
    card('Ana', status: :won, value_cents: 50_000)

    expect(described_class.new(account, source_id).deals).to eq(cards: 1, won: 1, won_value: nil)
    expect(described_class.new(account, []).deals(with_value: true)).to eq(cards: 0, won: 0, won_value: [])
  end
end

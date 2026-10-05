require 'rails_helper'

# #1002 — campaign marks on the CRM card (K3) and in the campaign filter (K6).
RSpec.describe CampaignJourney::CampaignMarks do
  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CAMPAIGN_JOURNEY_ENABLED: 'true') { example.run }
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:inbox) { create_crm_inbox(account: account, members: [user]) }
  let(:contact) { account.contacts.create!(name: 'Ana', phone_number: '+5511987654321') }
  let(:visibility) do
    Crm::Conversations::Visibility.new(account: account, user: user, account_user: user.account_users.find_by!(account: account))
  end
  let(:email_campaign) { create(:email_campaign, account: account, name: 'Novidades de outubro') }
  let(:whatsapp_inbox) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox }
  let(:whatsapp_campaign) { create(:campaign, account: account, inbox: whatsapp_inbox, title: 'Renovação auto — outubro', campaign_type: :one_off) }

  # Card with a link origin and the marks of two campaigns, on two linked conversations.
  def card_with_link_and_two_campaigns
    primary = create_crm_conversation(account: account, inbox: inbox, contact: contact)
    linked = create_crm_conversation(account: account, inbox: inbox, contact: contact)
    on_day(1) { Ctwa::CampaignBuilder.attribute!(primary, source_id: 'link:ABC234', source_type: 'tracked_link', headline: 'Feira 2026') }
    on_day(2) { described_class.mark!(linked.reload, email_campaign) }
    on_day(3) { described_class.mark!(primary.reload, whatsapp_campaign) }
    card_for(primary, linked)
  end

  def on_day(day, &)
    travel_to(Time.zone.parse("2026-10-0#{day} 10:00"), &)
  end

  def card_for(primary, linked)
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Ana', conversation_id: primary.id,
                                     inbox_id: inbox.id, contact_id: contact.id)
    Crm::CardConversation.create!(account: account, card: card, conversation: linked)
    card
  end

  it 'K3: the card lists the link and the two campaigns in order (first + 2)' do
    card = card_with_link_and_two_campaigns

    campaigns = Crm::Cards::PayloadBuilder.aggregated_campaigns_for(card, conversation_visibility: visibility)

    expect(campaigns.pluck(:source, :headline)).to eq(
      [['tracked_link', 'Feira 2026'], ['campaign_email', 'Novidades de outubro'], ['campaign_whatsapp', 'Renovação auto — outubro']]
    )
    expect(campaigns.size - 1).to eq(2)
  end

  it 'K6: the card filter matches cards marked with the campaign' do
    card = card_with_link_and_two_campaigns
    pipeline, stage = create_crm_pipeline(account: account, user: user, name: 'Outro funil')
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Sem campanha')

    result = Crm::Cards::FilterQuery.new(
      scope: account.crm_cards, params: { campaign_source_ids: "campaign:email:#{email_campaign.id}" }, conversation_visibility: visibility
    ).perform

    expect(result).to contain_exactly(card)
  end

  it 'does not take the row lock again for a campaign already marked' do
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact)
    described_class.mark!(conversation, email_campaign)

    expect(Ctwa::CampaignBuilder).not_to receive(:attribute!)
    expect(described_class.mark!(conversation.reload, email_campaign)).to be(false)
  end
end

require 'rails_helper'

# Card da ponte landing page → WhatsApp (#1011): UTMs nos toques e formulário da página.
RSpec.describe Crm::Cards::PayloadBuilder do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create_crm_inbox(account: account, members: [admin]) }
  let(:lead_form) do
    { 'link_code' => 'ABC234', 'captured_at' => '2026-10-05T12:00:00Z',
      'fields' => [{ 'key' => 'destination', 'label' => 'Destino', 'value' => 'América do Norte - EUA' },
                   { 'key' => 'ages', 'label' => 'Idades', 'value' => '72' }] }
  end
  let(:site_touch) do
    { 'source' => 'meta_paid', 'source_id' => 'site:ABC234:120211', 'source_type' => 'bridge', 'headline' => 'LP · Viagem EUA',
      'source_url' => 'https://placement.com.br/seguro-viagem', 'utm_source' => 'meta', 'utm_campaign' => 'Viagem EUA',
      'utm_term' => 'Conjunto 60+', 'utm_content' => 'Video 2', 'utm_id' => '120211', 'touched_at' => '2026-10-05T12:01:00Z' }
  end

  def create_card_with(additional_attributes)
    contact = account.contacts.create!(name: 'Lead LP', phone_number: "+55119#{rand(10_000_000..99_999_999)}")
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact)
    conversation.update!(additional_attributes: conversation.additional_attributes.merge(additional_attributes))
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Lead LP', conversation_id: conversation.id,
                                     inbox_id: conversation.inbox_id, contact_id: conversation.contact_id)
    [card, conversation]
  end

  def payload_for(card, user)
    described_class.new(card, user: user, account_user: user.account_users.find_by(account: account)).perform
  end

  it 'expõe utm_campaign/term/content/id nos toques e o formulário da conversa principal' do
    card, conversation = create_card_with('campaign_touches' => [site_touch], 'lead_form' => lead_form.merge('extra' => 'não vaza'))

    payload = payload_for(card, admin)

    expect(payload[:campaigns]).to eq(
      [{ source: 'meta_paid', source_id: 'site:ABC234:120211', source_type: 'bridge', headline: 'LP · Viagem EUA',
         source_url: 'https://placement.com.br/seguro-viagem', utm_campaign: 'Viagem EUA', utm_term: 'Conjunto 60+',
         utm_content: 'Video 2', utm_id: '120211', campaign_name: nil, adset_name: nil, ad_name: nil, ad_preview_url: nil, ad_thumbnail_url: nil,
         touched_at: '2026-10-05T12:01:00Z', conversation_id: conversation.id }]
    )
    expect(payload[:lead_form]).to eq(lead_form)
  end

  it 'não expõe o formulário para quem não vê a conversa principal' do
    outsider = create(:user, account: account, role: :agent)
    card, = create_card_with('campaign_touches' => [site_touch], 'lead_form' => lead_form)

    payload = payload_for(card, outsider)

    expect(payload).not_to have_key(:lead_form)
    expect(payload[:campaigns]).to eq([])
  end

  it 'omite lead_form quando a conversa não tem formulário ou o formato é inválido' do
    card, = create_card_with('campaign_touches' => [site_touch])
    expect(payload_for(card, admin)).not_to have_key(:lead_form)

    broken_card, = create_card_with('lead_form' => { 'fields' => 'texto' })
    expect(payload_for(broken_card, admin)).not_to have_key(:lead_form)
  end
end

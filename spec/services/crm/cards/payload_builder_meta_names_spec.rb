require 'rails_helper'

# Card mostra os nomes da Meta resolvidos nos toques (#1034).
RSpec.describe Crm::Cards::PayloadBuilder do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create_crm_inbox(account: account, members: [admin]) }

  it 'expõe campaign_name, adset_name, ad_name e touched_at em cada toque, sem chaves internas' do
    contact = account.contacts.create!(name: 'Lead', phone_number: '+5511977776666')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact)
    touch = { 'source' => 'meta_ctwa', 'source_id' => '120254710067060999', 'headline' => 'Fale conosco', 'ctwa_clid' => 'segredo-clid',
              'campaign_name' => 'Viagem EUA', 'adset_name' => 'Conjunto 60+', 'ad_name' => 'Video 2', 'touched_at' => '2026-10-01T12:00:00Z' }
    conversation.update!(additional_attributes: { 'campaign' => touch, 'campaign_touches' => [touch] })
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Lead', conversation_id: conversation.id,
                                     inbox_id: conversation.inbox_id, contact_id: conversation.contact_id)

    item = described_class.campaign_touches_for(conversation).sole
    payload = described_class.new(card, user: admin, account_user: admin.account_users.find_by(account: account)).perform

    expect(item).to include(campaign_name: 'Viagem EUA', adset_name: 'Conjunto 60+', ad_name: 'Video 2',
                            touched_at: '2026-10-01T12:00:00Z', conversation_id: conversation.id)
    expect(item).not_to have_key(:ctwa_clid)
    expect(payload[:campaigns].sole).to include(campaign_name: 'Viagem EUA', adset_name: 'Conjunto 60+', ad_name: 'Video 2')
  end

  it 'toque sem nome expõe as chaves com nil (o rótulo cai no utm_*)' do
    contact = account.contacts.create!(name: 'Lead 2', phone_number: '+5511966665555')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact)
    conversation.update!(additional_attributes: { 'campaign_touches' => [{ 'source' => 'meta_paid', 'utm_campaign' => '120254710067060416' }] })

    item = described_class.campaign_touches_for(conversation).sole

    expect(item).to include(campaign_name: nil, adset_name: nil, ad_name: nil, utm_campaign: '120254710067060416')
  end
end

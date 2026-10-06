require 'rails_helper'

# Resolução retroativa dos nomes da Meta ao salvar a credencial (#1034).
RSpec.describe Crm::MetaAds::BackfillJob do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create_crm_inbox(account: account, members: [admin]) }
  let(:campaign_id) { '120254710067060416' }
  let(:other_campaign_id) { '120254710067060417' }

  def conversation_with(touches, updated_at: Time.current)
    contact = account.contacts.create!(name: 'Lead', phone_number: "+55119#{rand(10_000_000..99_999_999)}")
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact)
    conversation.update!(additional_attributes: { 'campaign' => touches.first, 'campaign_touches' => touches })
    conversation.update_columns(updated_at: updated_at) # rubocop:disable Rails/SkipsModelValidations
    conversation
  end

  def site_touch(id, touched_at:, extra: {})
    { 'source' => 'meta_paid', 'source_id' => "site:ABC234:#{id}", 'headline' => "LP · #{id}", 'utm_campaign' => id,
      'touched_at' => touched_at.utc.iso8601 }.merge(extra)
  end

  it 'resolve em lote só os toques dos últimos 90 dias com ID e sem nome' do
    create_meta_ads_connection(account)
    recent = conversation_with([site_touch(campaign_id, touched_at: 10.days.ago)])
    old = conversation_with([site_touch(other_campaign_id, touched_at: 120.days.ago)], updated_at: 120.days.ago)
    old_touch_recent_conversation = conversation_with([site_touch(other_campaign_id, touched_at: 100.days.ago)])
    named = conversation_with([site_touch(other_campaign_id, touched_at: 5.days.ago, extra: { 'campaign_name' => 'Já tem' })])
    no_id = conversation_with([site_touch('viagem-eua', touched_at: 5.days.ago)])
    graph = stub_meta_object(id: campaign_id, fields: 'name,account_id', body: { id: campaign_id, name: 'Viagem EUA' })

    described_class.perform_now(account.id)

    expect(graph).to have_been_requested.once
    expect(meta_object_requests).to have_been_made.once
    expect(recent.reload.additional_attributes['campaign_touches'].sole).to include('campaign_name' => 'Viagem EUA',
                                                                                    'headline' => 'LP · Viagem EUA')
    [old, old_touch_recent_conversation, no_id].each do |conversation|
      expect(conversation.reload.additional_attributes['campaign_touches'].sole).not_to have_key('campaign_name')
    end
    expect(named.reload.additional_attributes['campaign_touches'].sole['campaign_name']).to eq('Já tem')
  end

  it 'busca cada ID uma vez só, mesmo repetido em várias conversas' do
    create_meta_ads_connection(account)
    first = conversation_with([site_touch(campaign_id, touched_at: 1.day.ago)])
    second = conversation_with([site_touch(other_campaign_id, touched_at: 2.days.ago)])
    conversation_with([site_touch(campaign_id, touched_at: 3.days.ago)])
    graph_a = stub_meta_object(id: campaign_id, fields: 'name,account_id', body: { id: campaign_id, name: 'A' })
    graph_b = stub_meta_object(id: other_campaign_id, fields: 'name,account_id', body: { id: other_campaign_id, name: 'B' })

    described_class.perform_now(account.id)

    expect(graph_a).to have_been_requested.once
    expect(graph_b).to have_been_requested.once
    expect(first.reload.additional_attributes['campaign_touches'].sole['campaign_name']).to eq('A')
    expect(second.reload.additional_attributes['campaign_touches'].sole['campaign_name']).to eq('B')
  end

  it 'ID que a Meta não resolve (erro 100) em N conversas: exatamente uma chamada, agora e na próxima passada' do
    create_meta_ads_connection(account)
    conversations = Array.new(5) { conversation_with([site_touch('999999999', touched_at: 1.day.ago)]) }
    graph = stub_meta_object(id: '999999999', fields: 'name,account_id', status: 400, body: meta_graph_error(100, 'Object does not exist'))

    2.times { described_class.perform_now(account.id) }

    expect(meta_object_requests).to have_been_made.once
    expect(graph).to have_been_requested.once
    conversations.each { |conversation| expect(conversation.reload.additional_attributes['campaign_touches'].sole).not_to have_key('campaign_name') }
  end

  it 'limite de taxa: uma chamada só, sem tentar conversa a conversa' do
    create_meta_ads_connection(account)
    3.times { conversation_with([site_touch(campaign_id, touched_at: 1.day.ago)]) }
    stub_meta_object(id: campaign_id, fields: 'name,account_id', status: 400, body: meta_graph_error(17, 'User request limit reached'))

    described_class.perform_now(account.id)

    expect(meta_object_requests).to have_been_made.once
    expect(Crm::MetaAdsConnection.find_by(account_id: account.id).status).to eq('active')
  end

  it 'não toca outra conta' do
    create_meta_ads_connection(account)
    other_account = create(:account)
    other_inbox = create_crm_inbox(account: other_account)
    contact = other_account.contacts.create!(name: 'Outro', phone_number: '+5511988887777')
    other = create_crm_conversation(account: other_account, inbox: other_inbox, contact: contact)
    other.update!(additional_attributes: { 'campaign_touches' => [site_touch(campaign_id, touched_at: 1.day.ago)] })

    described_class.perform_now(account.id)

    expect(meta_object_requests).not_to have_been_made
  end

  it 'sem credencial ativa não faz nada' do
    create_meta_ads_connection(account, status: 'invalid')
    conversation_with([site_touch(campaign_id, touched_at: 1.day.ago)])

    described_class.perform_now(account.id)

    expect(meta_object_requests).not_to have_been_made
  end
end

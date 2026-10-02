require 'rails_helper'

RSpec.describe 'CRM conversation-derived campaign visibility', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent_and_membership) { create_crm_agent(account: account) }
  let(:agent) { agent_and_membership.first }
  let(:membership) { agent_and_membership.last }
  let(:inbox) { create_crm_inbox(account: account, members: [admin, agent]) }
  let(:hidden_inbox) { create_crm_inbox(account: account, members: [admin]) }
  let(:contact) { create(:contact, account: account, name: 'Shared person') }
  let(:primary) { create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: agent) }
  let(:secondary) { create_crm_conversation(account: account, inbox: hidden_inbox, contact: contact, assignee: admin) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:card) do
    account.crm_cards.create!(pipeline: pipeline_and_stage.first, stage: pipeline_and_stage.last, owner: agent,
                              contact: contact, inbox: inbox, primary_conversation: primary, title: 'Shared negotiation', value_cents: 123_450)
  end
  let(:api) { "/api/v1/accounts/#{account.id}/crm" }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true') { example.run }
  end

  before do
    primary.update!(additional_attributes: { campaign_source_ids: ['visible-ad'], campaign_touches: [
                      { source: 'meta_ctwa', source_id: 'visible-ad', headline: 'Permitted campaign', touched_at: '2026-09-20T12:00:00Z' }
                    ] })
    secondary.update!(additional_attributes: { campaign_source_ids: ['restricted-ad'], campaign_touches: [
                        { source: 'meta_ctwa', source_id: 'restricted-ad', headline: 'Restricted campaign title', source_url: 'https://restricted.example/ad',
                          body: 'Never expose raw body', ctwa_clid: 'Never expose click id', touched_at: '2026-09-19T12:00:00Z' }
                      ] })
    card.card_conversations.create!(account: account, conversation: secondary, linked_by: admin)
  end

  %w[detail list board].each do |surface|
    it "excludes a restricted secondary conversation from #{surface} without hiding the permitted card" do
      path = { 'detail' => "/cards/#{card.id}", 'list' => '/cards', 'board' => '/kanban' }.fetch(surface)
      get api + path, params: { pipeline_id: card.pipeline_id }, headers: auth_headers(agent)
      expect(response).to have_http_status(:ok)
      payload = response.parsed_body.fetch('payload')
      row = case surface
            when 'detail' then payload
            when 'list' then payload.find { |item| item['id'] == card.id }
            else payload.fetch('stages').flat_map { |stage| stage['cards'] }.find { |item| item['id'] == card.id }
            end
      expect(row.fetch('campaigns').pluck('source_id')).to eq(['visible-ad'])
      expect(row['id']).to eq(card.id)
      expect(row['value_cents']).to eq(123_450)
      expect(response.body).not_to include('restricted-ad', 'Restricted campaign title', 'https://restricted.example/ad', 'Never expose')
    end
  end

  it 'retains all permitted touches in original temporal order for administrators without raw bodies or click ids' do
    get "#{api}/cards/#{card.id}", headers: auth_headers(admin)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'campaigns').pluck('source_id')).to eq(%w[restricted-ad visible-ad])
    expect(response.body).not_to include('Never expose')
  end

  %w[cards kanban cards/summaries].each do |surface|
    it "does not reveal a hidden campaign match or its count through #{surface} filters" do
      get "#{api}/#{surface}", params: { pipeline_id: card.pipeline_id, campaign_source_ids: 'restricted-ad', include_counts: true,
                                         group_by: 'stage' }, headers: auth_headers(agent)
      expect(response).to have_http_status(:ok)
      case surface
      when 'cards'
        expect(response.parsed_body['payload']).to eq([])
        expect(response.parsed_body.dig('meta', 'count')).to eq(0)
      when 'kanban'
        stages = response.parsed_body.dig('payload', 'stages')
        expect(stages.flat_map { |stage| stage['cards'] }).to eq([])
        expect(stages.sum { |stage| stage['cards_count'] }).to eq(0)
      else
        expect(response.parsed_body.dig('payload', 'groups')).to eq([])
      end
    end
  end

  it 'retains a visible campaign filter match and the commercial count' do
    get "#{api}/cards", params: { campaign_source_ids: 'visible-ad' }, headers: auth_headers(agent)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload'].pluck('id')).to eq([card.id])
    expect(response.parsed_body.dig('meta', 'count')).to eq(1)
  end

  it 'honors assigned-only rules even when the requester belongs to the secondary inbox' do
    hidden_inbox.add_members([agent.id])
    account.crm_inbox_settings.create!(inbox: hidden_inbox, visibility_mode: :assigned_only)
    get "#{api}/cards/#{card.id}", headers: auth_headers(agent)
    expect(response.parsed_body.dig('payload', 'campaigns').pluck('source_id')).to eq(['visible-ad'])
    get "#{api}/cards", params: { campaign_source_ids: 'restricted-ad' }, headers: auth_headers(agent)
    expect(response.parsed_body['payload']).to eq([])
  end

  it 'includes the secondary campaign after the same requester becomes a permitted participant' do
    hidden_inbox.add_members([agent.id])
    account.crm_inbox_settings.create!(inbox: hidden_inbox, visibility_mode: :assigned_only)
    secondary.conversation_participants.create!(account: account, user: agent)
    get "#{api}/cards/#{card.id}", headers: auth_headers(agent)
    expect(response.parsed_body.dig('payload', 'campaigns').pluck('source_id')).to eq(%w[restricted-ad visible-ad])
    get "#{api}/cards", params: { campaign_source_ids: 'restricted-ad' }, headers: auth_headers(agent)
    expect(response.parsed_body['payload'].pluck('id')).to eq([card.id])
  end

  it 'does not reveal labels that only exist on an inaccessible primary conversation' do
    label = account.labels.create!(title: 'restricted-conversation-label')
    secondary.add_labels([label.title])
    card.update!(primary_conversation: secondary)
    get "#{api}/cards", params: { label_ids: label.id }, headers: auth_headers(agent)
    expect(response.parsed_body['payload']).to eq([])
    expect(response.parsed_body.dig('meta', 'count')).to eq(0)
  end

  it 'preserves independent shared-contact labels even when the primary conversation is hidden' do
    label = account.labels.create!(title: 'shared-contact-label')
    contact.add_labels([label.title])
    card.update!(primary_conversation: secondary)
    get "#{api}/cards", params: { label_ids: label.id }, headers: auth_headers(agent)
    expect(response.parsed_body['payload'].pluck('id')).to eq([card.id])
    expect(response.parsed_body['payload'].first['contact_labels']).to include(label.title)
    expect(response.parsed_body['payload'].first['campaigns']).to eq([])
  end

  it 'serializes the websocket payload separately for each recipient' do
    calls = []
    allow(ActionCableBroadcastJob).to receive(:perform_later) { |tokens, _event, payload| calls << { tokens: tokens, payload: payload } }
    Crm::Cards::Broadcaster.broadcast(card, Events::Types::CRM_CARD_UPDATED)
    agent_payload = calls.find { |call| call[:tokens].include?(agent.pubsub_token) }.fetch(:payload)
    admin_payload = calls.find { |call| call[:tokens].include?(admin.pubsub_token) }.fetch(:payload)
    expect(agent_payload[:campaigns].pluck(:source_id)).to eq(['visible-ad'])
    expect(admin_payload[:campaigns].pluck(:source_id)).to eq(%w[restricted-ad visible-ad])
  end

  it 'does not count cards from a restricted inbox in the stage total' do
    account.crm_cards.create!(pipeline: card.pipeline, stage: card.stage, inbox: hidden_inbox, owner: admin, title: 'Restricted card')
    get "#{api}/kanban", params: { pipeline_id: card.pipeline_id, include_counts: true }, headers: auth_headers(agent)
    stage = response.parsed_body.dig('payload', 'stages').find { |item| item['id'] == card.stage_id }
    expect(stage['cards'].pluck('id')).to eq([card.id])
    expect(stage['cards_count']).to eq(1)
    expect(stage['total_cards_count']).to eq(1)
  end

  it 'deduplicates a legacy primary that also has a join row while retaining legitimate campaign history' do
    card.card_conversations.create!(account: account, conversation: primary, linked_by: admin, is_primary: true)
    get "#{api}/cards/#{card.id}", headers: auth_headers(admin)
    expect(response.parsed_body.dig('payload', 'campaigns').pluck('source_id')).to eq(%w[restricted-ad visible-ad])
  end

  it 'removes secondary campaign details on the request after inbox access is revoked' do
    hidden_inbox.add_members([agent.id])
    get "#{api}/cards/#{card.id}", headers: auth_headers(agent)
    expect(response.parsed_body.dig('payload', 'campaigns').pluck('source_id')).to include('restricted-ad')
    hidden_inbox.inbox_members.where(user_id: agent.id).destroy_all
    get "#{api}/cards/#{card.id}", headers: auth_headers(agent)
    expect(response.parsed_body.dig('payload', 'campaigns').pluck('source_id')).to eq(['visible-ad'])
  end

  it 'keeps a permitted secondary source consistent with filters when the primary conversation is hidden' do
    card.card_conversations.create!(account: account, conversation: primary, linked_by: admin)
    card.update!(primary_conversation: secondary)
    get "#{api}/cards", params: { campaign_source_ids: 'visible-ad' }, headers: auth_headers(agent)
    expect(response.parsed_body['payload'].pluck('id')).to eq([card.id])
    expect(response.parsed_body['payload'].first.fetch('campaigns').pluck('source_id')).to eq(['visible-ad'])
    get "#{api}/kanban", params: { pipeline_id: card.pipeline_id, campaign_source_ids: 'visible-ad' }, headers: auth_headers(agent)
    rows = response.parsed_body.dig('payload', 'stages').flat_map { |stage| stage['cards'] }
    expect(rows.pluck('id')).to eq([card.id])
    expect(rows.first.fetch('campaigns').pluck('source_id')).to eq(['visible-ad'])
    expect(rows.first['conversation_id']).to be_nil
    expect(response.body).not_to include('restricted-ad', 'Restricted campaign title')
  end

  it 'exports only the first authorized campaign, not the earlier restricted source' do
    role = create(:custom_role, account: account, permissions: %w[crm_view crm_export])
    membership.update!(custom_role: role)
    get "#{api}/cards/export", params: { pipeline_id: card.pipeline_id }, headers: auth_headers(agent)
    expect(response).to have_http_status(:ok)
    Zip::File.open_buffer(response.body) do |zip|
      text = zip.read('xl/sharedStrings.xml')
      expect(text).to include('Permitted campaign')
      expect(text).not_to include('Restricted campaign title', 'restricted.example', 'restricted-ad')
    end
  end
end

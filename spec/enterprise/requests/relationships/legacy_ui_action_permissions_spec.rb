require 'rails_helper'

RSpec.describe 'Legacy conversation UI permission boundaries', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:role) { create(:custom_role, account: account, permissions: %w[conversation_manage contact_view crm_view]) }
  let(:contact) { create(:contact, account: account, name: 'Preserved person') }
  let(:inbox) { create_crm_inbox(account: account, members: [agent, admin]) }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: agent) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:card) do
    account.crm_cards.create!(pipeline: pipeline_and_stage.first, stage: pipeline_and_stage.last, contact: contact,
                              primary_conversation: conversation, inbox: inbox, owner: agent, title: 'Preserved negotiation')
  end
  let(:follow_up) do
    account.crm_follow_ups.create!(card: card, contact: contact, created_by: admin, title: 'Preserved reminder',
                                   follow_up_type: :task, automation_mode: :reminder_only, due_at: 1.day.from_now, timezone: 'UTC')
  end
  let(:headers) { agent.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}" }

  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true' do
      example.run
    end
  end

  before do
    agent.account_users.find_by!(account: account).update!(custom_role: role)
    follow_up
  end

  [
    [:delete, :card, {}],
    [:patch, :card, { card: { title: 'Forbidden change' } }],
    [:post, :reset, {}],
    [:post, :complete, {}],
    [:post, :cancel, {}],
    [:post, :create_follow_up, {}],
    [:post, :from_conversation, {}],
    [:patch, :contact, { additional_attributes: { crm_ai_followup_disabled: true } }]
  ].each do |verb, action, data|
    it "keeps conversation management from authorizing #{action} (#{verb})" do
      paths = {
        card: "#{base}/crm/cards/#{card.id}", reset: "#{base}/crm/cards/#{card.id}/reset_auto_followup",
        complete: "#{base}/crm/follow_ups/#{follow_up.id}/complete", cancel: "#{base}/crm/follow_ups/#{follow_up.id}/cancel",
        create_follow_up: "#{base}/crm/follow_ups", from_conversation: "#{base}/crm/cards/from_conversation",
        contact: "#{base}/contacts/#{contact.id}"
      }
      payload = data.deep_dup
      payload[:follow_up] = { card_id: card.id, title: 'Forbidden reminder', due_at: 2.days.from_now.iso8601 } if action == :create_follow_up
      if action == :from_conversation
        payload.merge!(conversation_display_id: conversation.display_id, pipeline_id: card.pipeline_id, stage_id: card.stage_id)
      end
      before = [contact.reload.attributes, card.reload.attributes, conversation.reload.attributes, follow_up.reload.attributes]
      counts = [Contact.count, Crm::Card.count, Crm::FollowUp.count, Crm::Activity.count, Message.count]
      public_send(verb, paths.fetch(action), params: payload, headers: headers, as: :json)
      expect(response).to have_http_status(:unauthorized)
      expect([contact.reload.attributes, card.reload.attributes, conversation.reload.attributes, follow_up.reload.attributes]).to eq(before)
      expect([Contact.count, Crm::Card.count, Crm::FollowUp.count, Crm::Activity.count, Message.count]).to eq(counts)
    end
  end

  it 'keeps the authorized conversation and reminder readable without granting shared-record editing' do
    get "#{base}/conversations/#{conversation.display_id}", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    get "#{base}/crm/follow_ups", params: { card_id: card.id }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload'].pluck('id')).to include(follow_up.id)
    patch "#{base}/contacts/#{contact.id}", params: { name: 'Forbidden' }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(contact.reload.name).to eq('Preserved person')
  end

  it 'allows the explicitly authorized reminder completion without changing the shared contact' do
    role.update!(permissions: role.permissions + ['crm_manage_cards'])
    before = contact.reload.attributes
    post "#{base}/crm/follow_ups/#{follow_up.id}/complete", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(follow_up.reload).to be_done
    expect(contact.reload.attributes).to eq(before)
  end
end

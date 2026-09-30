require 'rails_helper'

RSpec.describe 'CRM card contact links (M02)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:contact) { account.contacts.create!(name: 'Original private person', email: 'original@example.com') }
  let(:replacement) { account.contacts.create!(name: 'Replacement', email: 'replacement@example.com') }
  let(:inbox) { create_crm_inbox(account: account, members: [admin]) }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let(:card) do
    account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, owner: admin, title: 'Opportunity', value_cents: 250_000)
  end
  let(:path) { "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}/link_contact" }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true') { example.run }
  end

  it 'links a saved contact and preserves the opportunity fields' do
    card.update!(contact_id: nil)
    post path, params: { contact_id: replacement.id }, headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload']).to include(
      'id' => card.id, 'contact_id' => replacement.id, 'title' => 'Opportunity',
      'value_cents' => 250_000, 'stage_id' => stage.id
    )
    expect(card.reload.contact_id).to eq(replacement.id)
  end

  it 'returns a controlled 422 and preserves the primary conversation when the contact conflicts' do
    card.update!(primary_conversation: conversation)
    before = card.attributes

    expect do
      post path, params: { contact_id: replacement.id }, headers: auth_headers(admin)
    end.not_to change(Crm::Activity, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['attributes']).to eq(['contact'])
    expect(response.parsed_body['message']).to include(I18n.t('errors.crm.contact_conversation_conflict'))
    expect(card.reload.attributes).to eq(before)
    expect(conversation.reload.contact_id).to eq(contact.id)
  end

  it 'checks secondary conversations without exposing their content in the error' do
    card.card_conversations.create!(account: account, conversation: conversation, linked_by: admin)
    post path, params: { contact_id: replacement.id }, headers: auth_headers(admin)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).not_to include(contact.name, contact.email, conversation.uuid)
    expect(card.reload.contact_id).to eq(contact.id)
    expect(card.linked_conversations.pluck(:id)).to eq([conversation.id])
  end

  it 'can relink the owner of the existing conversations after an explicit unlink' do
    card.update!(primary_conversation: conversation)
    post "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}/unlink_contact", headers: auth_headers(admin)
    expect(response).to have_http_status(:ok)

    post path, params: { contact_id: contact.id }, headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(card.reload.contact_id).to eq(contact.id)
    expect(card.conversation_id).to eq(conversation.id)
  end

  it 'does not bypass the conflict by unlinking first' do
    card.update!(primary_conversation: conversation)
    post "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}/unlink_contact", headers: auth_headers(admin)
    expect(response).to have_http_status(:ok)

    post path, params: { contact_id: replacement.id }, headers: auth_headers(admin)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(card.reload.contact_id).to be_nil
    expect(card.conversation_id).to eq(conversation.id)
    expect(conversation.reload.contact_id).to eq(contact.id)
  end

  it 'does not duplicate the audit event or touch the card when a link is repeated' do
    post path, params: { contact_id: replacement.id }, headers: auth_headers(admin)
    expect(response).to have_http_status(:ok)
    before = card.reload.attributes

    expect do
      post path, params: { contact_id: replacement.id }, headers: auth_headers(admin)
    end.not_to change(Crm::Activity, :count)

    expect(response).to have_http_status(:ok)
    expect(card.reload.attributes).to eq(before)
  end

  it 'does not create conversations, messages, follow-ups or emails when linking' do
    card
    replacement
    counts = [Conversation.count, Message.count, Crm::FollowUp.count, ActionMailer::Base.deliveries.count]

    post path, params: { contact_id: replacement.id }, headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect([Conversation.count, Message.count, Crm::FollowUp.count, ActionMailer::Base.deliveries.count]).to eq(counts)
  end

  it 'rejects a contact ID from another account without disclosing its identity' do
    foreign_contact = create(:contact, email: 'private-foreign@example.com')
    original_id = card.contact_id
    post path, params: { contact_id: foreign_contact.id }, headers: auth_headers(admin)

    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(foreign_contact.email)
    expect(card.reload.contact_id).to eq(original_id)
    expect(card.activities).to be_empty
  end

  it 'rejects a card outside the authenticated account' do
    other_account = create(:account)
    outsider = create(:user, account: other_account, role: :administrator)
    original_id = card.contact_id

    post path, params: { contact_id: replacement.id }, headers: auth_headers(outsider)

    expect(response).to have_http_status(:unauthorized)
    expect(card.reload.contact_id).to eq(original_id)
    expect(card.activities).to be_empty
  end

  it 'requires authentication before changing a contact' do
    original_id = card.contact_id
    post path, params: { contact_id: replacement.id }

    expect(response).to have_http_status(:unauthorized)
    expect(card.reload.contact_id).to eq(original_id)
    expect(card.activities).to be_empty
  end
end

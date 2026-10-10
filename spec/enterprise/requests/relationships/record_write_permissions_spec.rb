require 'rails_helper'

RSpec.describe 'Shared relationship record write permissions', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:role) { create(:custom_role, account: account, permissions: %w[contact_view crm_view crm_manage_cards]) }
  let(:headers) { agent.create_new_auth_token }
  let(:company) { create(:company, account: account, name: 'Keep company', domain: 'keep.example') }
  let(:contact) { create(:contact, account: account, company: company, name: 'Keep person') }
  let(:other) { create(:contact, account: account, name: 'Other person') }
  let(:note) { contact.notes.create!(content: 'Keep note', user: admin) }
  let(:base) { "/api/v1/accounts/#{account.id}" }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:card) { account.crm_cards.create!(pipeline: pipeline_and_stage.first, stage: pipeline_and_stage.last, title: 'Keep deal', owner: agent) }

  before do
    account.enable_features!('companies', 'custom_attributes')
    agent.account_users.find_by!(account: account).update!(custom_role: role)
    allow(Crm::Config).to receive(:enabled?).and_return(true)
    contact
    other
    note
    card
    headers
  end

  [
    [:patch, :contact, { name: 'Forbidden change' }],
    [:patch, :contact, { custom_attributes: { job_title: 'Forbidden' } }],
    [:patch, :contact, { company_id: nil }],
    [:patch, :company, { company: { name: 'Forbidden company' } }],
    [:patch, :company, { company: { custom_attributes: { size: 2 } } }],
    [:post, :contact_notes, { note: { content: 'Forbidden note' } }],
    [:patch, :note, { note: { content: 'Forbidden update' } }],
    [:delete, :note, {}],
    [:post, :contact_labels, { labels: ['forbidden'] }],
    [:post, :company_contacts, {}],
    [:delete, :company_contact, {}],
    [:delete, :contact_avatar, {}],
    [:delete, :company_avatar, {}],
    [:post, :contact_opt_out, {}],
    [:post, :contact_customer, {}],
    [:post, :merge, {}],
    [:post, :bulk, { type: 'Contact', action_name: 'assign', labels: { add: ['forbidden'] } }],
    [:post, :contacts, { name: 'Forbidden person' }],
    [:post, :companies, { company: { name: 'Forbidden business' } }],
    [:post, :card_contact, { contact: { name: 'Forbidden CRM person' } }]
  ].each do |verb, target, input|
    it "denies #{verb} #{target} without shared-record management: #{input.keys.join(',')}" do
      paths = {
        contact: "#{base}/contacts/#{contact.id}", company: "#{base}/companies/#{company.id}",
        contact_notes: "#{base}/contacts/#{contact.id}/notes", note: "#{base}/contacts/#{contact.id}/notes/#{note.id}",
        contact_labels: "#{base}/contacts/#{contact.id}/labels", company_contacts: "#{base}/companies/#{company.id}/contacts",
        company_contact: "#{base}/companies/#{company.id}/contacts/#{contact.id}",
        contact_avatar: "#{base}/contacts/#{contact.id}/avatar", company_avatar: "#{base}/companies/#{company.id}/avatar",
        contact_opt_out: "#{base}/contacts/#{contact.id}/opt_out", contact_customer: "#{base}/contacts/#{contact.id}/customer",
        merge: "#{base}/actions/contact_merge", bulk: "#{base}/bulk_actions",
        contacts: "#{base}/contacts", companies: "#{base}/companies", card_contact: "#{base}/crm/cards/#{card.id}/contact"
      }
      params = input.deep_dup
      params[:contact_id] = other.id if target == :company_contacts
      if target == :merge
        params[:base_contact_id] = contact.id
        params[:mergee_contact_id] = other.id
      end
      params[:ids] = [contact.id] if target == :bulk
      before = [contact.reload.attributes, company.reload.attributes, note.reload.attributes, card.reload.attributes]
      counts = [Contact.count, Company.count, Crm::Card.count, Note.count, Crm::Activity.count, IdempotencyKey.count]
      public_send(verb, paths.fetch(target), params: params, headers: headers.merge('Idempotency-Key' => SecureRandom.uuid), as: :json)
      expect(response).to have_http_status(:unauthorized)
      expect([Contact.count, Company.count, Crm::Card.count, Note.count, Crm::Activity.count, IdempotencyKey.count]).to eq(counts)
      expect([contact.reload.attributes, company.reload.attributes, note.reload.attributes, card.reload.attributes]).to eq(before)
    end
  end

  it 'refuses new shared records through composite creation even when CRM card management is granted' do
    input = { card: { title: 'New deal', pipeline_id: pipeline_and_stage.first.id, stage_id: pipeline_and_stage.last.id,
                      relationship: { mode: 'new', contact: { name: 'New person' },
                                      company: { mode: 'new', attributes: { name: 'New company' } } } } }
    expect { post "#{base}/crm/cards", params: input, headers: headers.merge('Idempotency-Key' => SecureRandom.uuid), as: :json }
      .to not_change(Contact, :count).and not_change(Company, :count).and not_change(Crm::Card, :count).and not_change(IdempotencyKey, :count)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'preserves reading, existing-contact deals and standalone deals without requiring contact_manage' do
    get "#{base}/contacts/#{contact.id}", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    get "#{base}/companies/#{company.id}", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    [contact.id, nil].each do |id|
      input = { card: { title: 'Allowed deal', pipeline_id: pipeline_and_stage.first.id, stage_id: pipeline_and_stage.last.id, contact_id: id } }
      expect { post "#{base}/crm/cards", params: input, headers: headers.merge('Idempotency-Key' => SecureRandom.uuid), as: :json }
        .to change(Crm::Card, :count).by(1).and not_change(Contact, :count).and not_change(Company, :count)
      expect(response).to have_http_status(:created)
    end
  end

  it 'allows contact_manage to edit both shared records without granting deletion or CRM management' do
    role.update!(permissions: ['contact_manage'])
    patch "#{base}/contacts/#{contact.id}", params: { name: 'Allowed person' }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    patch "#{base}/companies/#{company.id}", params: { company: { name: 'Allowed company' } }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(contact.reload.name).to eq('Allowed person')
    expect(company.reload.name).to eq('Allowed company')
    delete "#{base}/companies/#{company.id}", headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    patch "#{base}/crm/cards/#{card.id}", params: { card: { title: 'Not allowed' } }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rechecks the current role after a write permission is revoked' do
    role.update!(permissions: ['contact_manage'])
    patch "#{base}/contacts/#{contact.id}", params: { name: 'Confirmed' }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    role.update!(permissions: ['contact_view'])
    patch "#{base}/contacts/#{contact.id}", params: { name: 'Rejected' }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(contact.reload.name).to eq('Confirmed')
  end

  it 'preserves standard agent and administrator writes' do
    agent.account_users.find_by!(account: account).update!(custom_role: nil)
    [headers, admin.create_new_auth_token].each do |auth|
      patch "#{base}/contacts/#{contact.id}", params: { name: 'Allowed' }, headers: auth, as: :json
      expect(response).to have_http_status(:ok)
      patch "#{base}/companies/#{company.id}", params: { company: { name: 'Allowed' } }, headers: auth, as: :json
      expect(response).to have_http_status(:ok)
    end
  end
end

require 'rails_helper'

# Excluir de vez (#2096) é só de administrador também no EE: nenhuma função personalizada abre, nem a que tem tudo do CRM
# (crm_admin), nem a de excluir contato (contact_delete) com os cards junto.
RSpec.describe 'Excluir de vez com função personalizada', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:contact) { account.contacts.create!(name: 'Cliente', phone_number: '+5511999990003') }
  let(:card) do
    account.crm_cards.create!(pipeline: pipeline, stage: pipeline_and_stage.last, contact: contact, title: 'Pedido', status: :archived)
  end
  let(:base) { "/api/v1/accounts/#{account.id}" }

  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run }
  end

  before { account.enable_features!(:crm_arquivados) }

  def give_role(permissions)
    role = create(:custom_role, account: account, permissions: permissions)
    agent.account_users.find_by!(account: account).update!(custom_role: role)
  end

  it 'recusa card com crm_admin e crm_delete_cards' do
    give_role(%w[crm_view crm_admin crm_delete_cards crm_manage_cards])

    post "#{base}/crm/cards/permanent_delete", params: { card_ids: [card.id], confirmation: 'EXCLUIR' },
                                               headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:forbidden)
    expect(card.reload).to be_present
  end

  it 'recusa funil com crm_admin e crm_manage_pipelines' do
    give_role(%w[crm_view crm_admin crm_manage_pipelines])
    pipeline.archived!

    post "#{base}/crm/pipelines/#{pipeline.id}/permanent_delete", params: { confirmation: pipeline.name },
                                                                  headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:forbidden)
    expect(pipeline.reload).to be_present
  end

  it 'deixa excluir o contato com contact_delete, mas não apagar os cards dele junto' do
    give_role(%w[contact_view contact_delete crm_admin])
    card

    %w[delete keep].each do |modo|
      post "#{base}/crm/contacts/#{contact.id}/permanent_delete",
           params: { confirmation: 'EXCLUIR', cards: modo }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end
    get "#{base}/crm/contacts/#{contact.id}/permanent_delete_preview", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect([Contact.exists?(contact.id), Crm::Card.exists?(card.id)]).to eq([true, true])

    # O DELETE de sempre, aberto pela chave, mantém o card sem dado pessoal (LGPD).
    delete "#{base}/contacts/#{contact.id}", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(card.reload.attributes.slice('contact_id', 'title')).to eq('contact_id' => nil, 'title' => "Removed customer ##{card.id}")
  end

  it 'recusa a prévia do funil com crm_admin e crm_manage_pipelines' do
    give_role(%w[crm_view crm_admin crm_manage_pipelines])

    get "#{base}/crm/pipelines/#{pipeline.id}/permanent_delete_preview", headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:forbidden)
  end
end

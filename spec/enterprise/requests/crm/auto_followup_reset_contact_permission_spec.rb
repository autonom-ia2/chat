require 'rails_helper'

# chat#1325: a recusa do contato vale para a conta inteira. O reset do follow-up só a tira de quem também pode editar o
# contato (ContactPolicy#update?, no EE relationship_record_write?: contact_manage na função). Sem isso, limpa só o card.
RSpec.describe 'CRM auto follow-up reset and the contact opt-out permission', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, name: 'Pediu para parar') }
  let(:inbox) { create_crm_inbox(account: account, members: [agent, admin]) }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: agent) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:card) do
    account.crm_cards.create!(
      pipeline: pipeline_and_stage.first, stage: pipeline_and_stage.last, contact: contact, primary_conversation: conversation,
      inbox: inbox, owner: agent, title: 'Negociação',
      metadata: { 'ai' => { 'auto_followup_state' => { 'opted_out' => true, 'opt_out_contact_id' => contact.id } } }
    )
  end
  let(:url) { "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}/reset_auto_followup" }

  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true' do
      example.run
    end
  end

  before { contact.opt_out!(source: 'follow_up_reply') }

  def give_role(permissions)
    role = create(:custom_role, account: account, permissions: permissions)
    agent.account_users.find_by!(account: account).update!(custom_role: role)
  end

  def card_state
    card.reload.metadata['ai']['auto_followup_state']
  end

  it 'IA do CRM no funil sem poder editar o contato: reseta o card e mantém a recusa do contato' do
    give_role(%w[crm_view crm_manage_ai contact_view])

    post url, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['contact_opt_out']).to eq('kept_no_permission')
    expect(card_state['opted_out']).to be(false)
    expect(contact.reload.opt_out_source).to eq('follow_up_reply')
  end

  it 'com permissão de editar o contato: reseta o card e libera a recusa' do
    give_role(%w[crm_view crm_manage_ai contact_view contact_manage])

    post url, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['contact_opt_out']).to eq('released')
    expect(card_state['opted_out']).to be(false)
    expect(contact.reload).not_to be_opted_out
  end

  # Documenta o comportamento atual: nem a policy nem o reset olham o status do card. O planner só re-arma card aberto,
  # então o card arquivado fica zerado, sem voltar a enviar.
  it 'card arquivado também pode ser resetado e libera a recusa' do
    card.update!(status: :archived)

    post url, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['contact_opt_out']).to eq('released')
    expect(card.reload).to be_archived
    expect(card_state['opted_out']).to be(false)
    expect(contact.reload).not_to be_opted_out
  end

  it 'card que nunca parou a pedido do cliente: a resposta diz none' do
    card.update!(metadata: { 'ai' => { 'auto_followup_state' => { 'active' => false } } })

    post url, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['contact_opt_out']).to eq('none')
    expect(contact.reload.opt_out_source).to eq('follow_up_reply')
  end
end

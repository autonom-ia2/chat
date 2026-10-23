require 'rails_helper'

# #2096, decisão do Rodrigo (23/10): a função personalizada só com contact_delete exclui o contato mesmo com cards que
# ela não vê; os cards ficam sem dado pessoal e a exclusão grava uma linha na Auditoria (quem fez, quantos cards e
# quantas reuniões, só ids e contagens). Vale para todo caminho de exclusão de contato com a flag crm_arquivados.
RSpec.describe 'Excluir contato com cards que a função não vê', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:contact) { account.contacts.create!(name: 'Cliente Sigiloso', phone_number: '+5511999990091') }
  let(:card) do
    pipeline, stage = pipeline_and_stage
    account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: 'Pedido Sigiloso', status: :open)
  end
  let!(:reuniao) { create_reuniao(account: account, card: card, user: admin, contact: contact, starts_at: 2.days.from_now) }
  let(:base) { "/api/v1/accounts/#{account.id}" }

  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run }
  end

  before do
    account.enable_features!(:crm_arquivados)
    role = CustomRole.create!(account: account, name: 'Só exclui contato', permissions: %w[contact_view contact_delete])
    agent.account_users.find_by!(account: account).update!(custom_role: role)
  end

  def auditoria
    Audited.audit_class.where(auditable: account, action: Crm::ExclusaoDefinitiva::ACAO).sole
  end

  it 'a função não vê o card' do
    get "#{base}/crm/cards/#{card.id}", headers: agent.create_new_auth_token, as: :json

    expect(response).not_to have_http_status(:success)
  end

  it 'DELETE contacts/:id: exclui, anonimiza o card, cancela a reunião e audita quem fez, só com ids e contagens' do
    delete "#{base}/contacts/#{contact.id}", headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect([Contact.exists?(contact.id), card.reload.title, reuniao.reload.status])
      .to eq([false, "Removed customer ##{card.id}", 'canceled'])
    expect(auditoria.user).to eq(agent)
    expect(auditoria.audited_changes)
      .to eq('alvo' => 'contato', 'cards_apagados' => 0, 'card_ids' => [], 'contact_id' => contact.id, 'modo' => 'keep',
             'cards_mantidos' => 1, 'card_ids_mantidos' => [card.id], 'reunioes_canceladas' => 1,
             'reunioes_so_aqui' => 0, 'canceled_meeting_ids' => [reuniao.id])
    expect(auditoria.audited_changes.to_json).not_to include('Sigiloso')
  end

  it 'exclusão em lote: audita com quem pediu, mesmo rodando num job' do
    params = { type: 'Contact', ids: [contact.id], action_name: 'delete' }
    perform_enqueued_jobs(only: Contacts::BulkActionJob) do
      post "#{base}/bulk_actions", params: params, headers: agent.create_new_auth_token, as: :json
    end

    expect(response).to have_http_status(:success)
    expect([Contact.exists?(contact.id), reuniao.reload.status]).to eq([false, 'canceled'])
    expect(auditoria.user).to eq(agent)
    expect(auditoria.audited_changes).to include('cards_mantidos' => 1, 'reunioes_canceladas' => 1)
  end

  it 'contato sem card nem reunião não grava linha' do
    outro = account.contacts.create!(name: 'Sem card', phone_number: '+5511999990092')

    delete "#{base}/contacts/#{outro.id}", headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(Audited.audit_class.where(auditable: account, action: Crm::ExclusaoDefinitiva::ACAO)).to be_empty
  end
end

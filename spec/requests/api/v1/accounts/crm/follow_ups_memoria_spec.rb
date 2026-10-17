require 'rails_helper'

# #1601: a marca `memoria` da tarefa de retomar é do servidor. Um PATCH que manda metadata não a apaga (senão a tarefa
# sem prazo viraria um lembrete comum, vencido e avisado pelo DueProcessor), e o cliente não a cria.
RSpec.describe 'CRM follow-ups API: marca da memória', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account) }
  let(:tarefa) do
    account.crm_follow_ups.create!(title: 'Responder ao cliente', due_at: Time.current, contact: contact, follow_up_type: :task,
                                   metadata: { 'memoria' => { 'tipo' => 'retomar_atendimento' } })
  end

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  it 'o PATCH com metadata mantém a marca e não deixa o cliente trocá-la' do
    corpo = { follow_up: { title: 'X', metadata: { source: 'x', memoria: { tipo: 'outro' } } } }
    patch "/api/v1/accounts/#{account.id}/crm/follow_ups/#{tarefa.id}", headers: admin.create_new_auth_token, params: corpo, as: :json

    expect(response).to have_http_status(:ok)
    expect(tarefa.reload.metadata).to include('memoria' => { 'tipo' => 'retomar_atendimento' }, 'source' => 'x')
  end

  it 'o cliente não cria a marca' do
    sem = account.crm_follow_ups.create!(title: 'Comum', due_at: 1.day.from_now, contact: contact, follow_up_type: :task)

    corpo = { follow_up: { metadata: { memoria: { tipo: 'retomar_atendimento' } } } }
    patch "/api/v1/accounts/#{account.id}/crm/follow_ups/#{sem.id}", headers: admin.create_new_auth_token, params: corpo, as: :json

    expect(sem.reload.metadata).not_to have_key('memoria')
  end
end

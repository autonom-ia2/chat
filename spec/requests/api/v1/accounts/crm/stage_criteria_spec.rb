require 'rails_helper'

# #1384: a tela de criar funil mostra o critério padrão e usa a IA antes de o funil existir.
RSpec.describe 'CRM stage criteria for an unsaved pipeline', type: :request do
  around do |example|
    previous_crm = ENV.fetch('CRM_KANBAN_ENABLED', nil)
    previous_ai = ENV.fetch('CRM_AI_ENABLED', nil)
    ENV['CRM_KANBAN_ENABLED'] = 'true'
    ENV['CRM_AI_ENABLED'] = 'true'
    example.run
  ensure
    previous_crm.nil? ? ENV.delete('CRM_KANBAN_ENABLED') : ENV['CRM_KANBAN_ENABLED'] = previous_crm
    previous_ai.nil? ? ENV.delete('CRM_AI_ENABLED') : ENV['CRM_AI_ENABLED'] = previous_ai
  end

  let!(:account_and_admin) { create_account_and_user }
  let(:account) { account_and_admin.first }
  let(:admin) { account_and_admin.last }
  let(:agent) do
    user = User.create!(name: 'Agente', email: "agente-#{SecureRandom.hex(4)}@example.com",
                        password: 'Passw0rd!23', confirmed_at: Time.current)
    AccountUser.create!(account: account, user: user, role: :agent)
    user
  end
  let(:base) { "/api/v1/accounts/#{account.id}/crm/stage_criteria" }
  let(:stages) { [{ name: 'Novo', description: '' }, { name: 'Proposta', description: 'Oferta enviada.' }] }

  it 'returns the server default criteria aligned with the requested names' do
    get "#{base}/defaults", params: { names: ['Novo', 'Em atendimento', 'Etapa 6'] }, headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body['payload']
    expect(payload.pluck('name')).to eq(['Novo', 'Em atendimento', 'Etapa 6'])
    expect(payload[0]['criteria']).to eq(Crm::Ai::DefaultStageCriteria.criteria_for('Novo'))
    expect(payload[1]['criteria']).to eq(Crm::Ai::DefaultStageCriteria.criteria_for('Em atendimento'))
    expect(payload[2]['criteria']).to eq('')
  end

  it 'refuses people who cannot create pipelines with AI' do
    get "#{base}/defaults", params: { names: ['Novo'] }, headers: auth_headers(agent)
    expect(response).to have_http_status(:unauthorized)

    post "#{base}/improve", params: { stages: stages, stage_index: 0 }, headers: auth_headers(agent), as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns 404 when CRM AI is disabled' do
    ENV['CRM_AI_ENABLED'] = 'false'

    get "#{base}/defaults", params: { names: ['Novo'] }, headers: auth_headers(admin)

    expect(response).to have_http_status(:not_found)
  end

  it 'rejects more stages than the AI limit, without calling the AI' do
    allow(Crm::Ai::StageCriteriaImprover).to receive(:new)
    too_many = Array.new(Crm::Ai::StageCriteriaImprover::MAX_STAGES + 1) { |index| { name: "Etapa #{index + 1}", description: '' } }

    post "#{base}/improve", params: { stages: too_many, stage_index: 0 }, headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(Crm::Ai::StageCriteriaImprover).not_to have_received(:new)
  end

  it 'rejects an index outside the supplied stages' do
    post "#{base}/improve", params: { stages: stages, stage_index: 2 }, headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'drafts a description with AI before the pipeline exists' do
    suggestion = { 'description' => 'Primeiro contato do cliente.', 'note' => '' }
    improver = instance_double(Crm::Ai::StageCriteriaImprover, perform: suggestion)
    allow(Crm::Ai::StageCriteriaImprover).to receive(:new).and_return(improver)

    expect do
      post "#{base}/improve", params: { pipeline_name: ' Funil Novo ', stages: stages, stage_index: 0 },
                              headers: auth_headers(admin), as: :json
    end.not_to change(Crm::Pipeline, :count)
    expect(response).to have_http_status(:accepted)

    Crm::Ai::InteractiveJob.perform_now(response.parsed_body['id'])
    get response.parsed_body['poll_url'], headers: auth_headers(admin)

    expect(response.parsed_body['status']).to eq('done')
    expect(response.parsed_body['result']).to eq(suggestion)
    expect(Crm::Ai::StageCriteriaImprover).to have_received(:new).with(
      pipeline: an_object_having_attributes(new_record?: true, account_id: account.id, name: 'Funil Novo'),
      stage_index: 0, language: 'en',
      stages: [{ name: 'Novo', description: '' }, { name: 'Proposta', description: 'Oferta enviada.' }]
    )
  end

  it 'still runs the saved pipeline flow with its own record' do
    pipeline, = create_crm_pipeline(account: account, user: admin)
    improver = instance_double(Crm::Ai::StageCriteriaImprover, perform: { 'description' => 'x', 'note' => '' })
    allow(Crm::Ai::StageCriteriaImprover).to receive(:new).and_return(improver)

    post "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/ai_settings/improve_criteria",
         params: { stages: stages, stage_index: 1 }, headers: auth_headers(admin), as: :json
    Crm::Ai::InteractiveJob.perform_now(response.parsed_body['id'])

    expect(Crm::Ai::StageCriteriaImprover).to have_received(:new).with(hash_including(pipeline: pipeline, stage_index: 1))
  end
end

require 'rails_helper'

# #1920: raio-x das frases e "Melhorar com IA" do "quando usar", pela mesma fila das IAs interativas do funil.
RSpec.describe 'CRM AI settings: frases com evidência', type: :request do
  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { example.run }
  end

  let(:account_and_admin) { create_account_and_user }
  let(:account) { account_and_admin.first }
  let(:admin) { account_and_admin.last }
  let(:pipeline) { create_crm_pipeline(account: account, user: admin).first }
  let(:agent) { create_crm_agent(account: account).first }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/ai_settings" }
  let(:stages) { [{ id: pipeline.stages.first.id, name: 'Novo Lead', description: 'Primeiro contato.' }] }

  # A vaga do raio-x mora no Redis, fora da transação do teste.
  around do |example|
    example.run
  ensure
    Redis::Alfred.delete("#{Crm::Ai::RaioXDasFrases::VAGA}funil:#{pipeline.id}")
  end

  def resultado_do_pedido
    Crm::Ai::InteractiveJob.perform_now(response.parsed_body['id'])
    get response.parsed_body['poll_url'], headers: auth_headers(admin)
    response.parsed_body
  end

  it 'roda o raio-x com as frases da tela' do
    raio_x = instance_double(Crm::Ai::RaioXDasFrases, perform: { total: 3, acertos_atual: 1, acertos_nova: 2 })
    allow(Crm::Ai::RaioXDasFrases).to receive(:new).and_return(raio_x)

    post "#{base}/criteria_xray", params: { stages: stages }, headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:accepted)
    expect(resultado_do_pedido).to include('status' => 'done', 'result' => { 'total' => 3, 'acertos_atual' => 1, 'acertos_nova' => 2 })
    expect(Crm::Ai::RaioXDasFrases).to have_received(:new)
      .with(pipeline: pipeline, stages: stages, cards: kind_of(ActiveRecord::Relation))
  end

  it 'não aceita um segundo raio-x do mesmo funil enquanto o primeiro vale' do
    allow(Crm::Ai::RaioXDasFrases).to receive(:new).and_return(instance_double(Crm::Ai::RaioXDasFrases, perform: {}))

    post "#{base}/criteria_xray", params: { stages: stages }, headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:accepted)
    post "#{base}/criteria_xray", params: { stages: stages }, headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:too_many_requests)
  end

  it 'recusa etapas inválidas no raio-x sem chamar a IA' do
    allow(Crm::Ai::RaioXDasFrases).to receive(:new)

    post "#{base}/criteria_xray", params: { stages: [{ name: ' ', description: '' }] }, headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(Crm::Ai::RaioXDasFrases).not_to have_received(:new)
  end

  it 'melhora o "quando usar" com o que está no formulário' do
    improver = instance_double(Crm::Ai::WhenToUseImprover, perform: { 'when_to_use' => 'Texto', 'note' => '' })
    allow(Crm::Ai::WhenToUseImprover).to receive(:new).and_return(improver)

    post "#{base}/improve_when_to_use", params: { funil: { counts_as_sale: false, when_to_use: 'Suporte', outro: 'x' } },
                                        headers: auth_headers(admin), as: :json

    expect(resultado_do_pedido).to include('status' => 'done', 'result' => { 'when_to_use' => 'Texto', 'note' => '' })
    expect(Crm::Ai::WhenToUseImprover).to have_received(:new)
      .with(pipeline: pipeline, language: 'en', funil: { counts_as_sale: 'false', when_to_use: 'Suporte' }, cards: kind_of(ActiveRecord::Relation))
  end

  it 'recusa o funil do formulário que não é um objeto' do
    allow(Crm::Ai::WhenToUseImprover).to receive(:new)

    post "#{base}/improve_when_to_use", params: { funil: [{ counts_as_sale: false }] }, headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post "#{base}/improve_criteria", params: { stages: stages, stage_index: 0, funil: [{ when_to_use: 'x' }] },
                                     headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Crm::Ai::WhenToUseImprover).not_to have_received(:new)
  end

  it 'passa o tipo e o "quando usar" da tela ao "Melhorar com IA" das etapas' do
    improver = instance_double(Crm::Ai::StageCriteriaImprover, perform: { 'description' => 'x', 'note' => '' })
    allow(Crm::Ai::StageCriteriaImprover).to receive(:new).and_return(improver)

    post "#{base}/improve_criteria", params: { stages: stages, stage_index: 0, funil: { counts_as_sale: true, when_to_use: '' } },
                                     headers: auth_headers(admin), as: :json
    resultado_do_pedido

    expect(Crm::Ai::StageCriteriaImprover).to have_received(:new)
      .with(hash_including(pipeline: pipeline, funil: { counts_as_sale: 'true', when_to_use: '' }))
  end

  it 'recusa quem não gerencia a IA do funil' do
    post "#{base}/criteria_xray", params: { stages: stages }, headers: auth_headers(agent), as: :json
    expect(response).to have_http_status(:unauthorized)

    post "#{base}/improve_when_to_use", params: {}, headers: auth_headers(agent), as: :json
    expect(response).to have_http_status(:unauthorized)
  end
end

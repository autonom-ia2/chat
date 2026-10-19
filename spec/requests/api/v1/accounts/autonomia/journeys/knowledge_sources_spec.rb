require 'rails_helper'

# Jornada "caminhos tristes" da base de conhecimento (Sources): agente inexistente,
# tenancy (agente/fonte de outra conta ou de outro agente) e kind inválido.
RSpec.describe 'Autonomia journeys - knowledge sources', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create_agent(account) }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  def create_agent(owner_account)
    Autonomia::Agents::Agent.create!(
      account: owner_account, name: "Agente #{SecureRandom.hex(3)}", agent_type: 'support', mode: :guided,
      status: :draft, enabled: false, actuation: :external
    )
  end

  def create_source(owner_agent)
    Autonomia::Agents::Source.create!(
      account: owner_agent.account, agent: owner_agent, source_type: 'txt', reference: 'faq.txt'
    )
  end

  it 'returns 404 when uploading a source to a nonexistent agent' do
    # Act
    post "/api/v1/accounts/#{account.id}/autonomia/agents/999999/sources",
         params: { source: { source_type: 'txt', reference: 'faq.txt' } },
         headers: administrator.create_new_auth_token, as: :json

    # Assert
    expect(response).to have_http_status(:not_found)
  end

  it 'returns 404 when uploading a source to an agent of another account' do
    # Arrange
    other_account = create(:account, internal_attributes: { 'autonomia_agents_enabled' => true })
    foreign_agent = create_agent(other_account)

    # Act — URL na conta A apontando para o agente da conta B (agents_scope bloqueia).
    post "/api/v1/accounts/#{account.id}/autonomia/agents/#{foreign_agent.id}/sources",
         params: { source: { source_type: 'txt', reference: 'faq.txt' } },
         headers: administrator.create_new_auth_token, as: :json

    # Assert
    expect(response).to have_http_status(:not_found)
    expect(foreign_agent.sources.count).to eq(0)
  end

  it 'returns 404 when deleting a source that belongs to a different agent' do
    # Arrange — fonte existe na MESMA conta, mas em outro agente (fetch_source escopa em @agent).
    sibling_agent = create_agent(account)
    foreign_source = create_source(sibling_agent)

    # Act
    delete "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/sources/#{foreign_source.id}",
           headers: administrator.create_new_auth_token, as: :json

    # Assert — nada apagado.
    expect(response).to have_http_status(:not_found)
    expect(Autonomia::Agents::Source.find_by(id: foreign_source.id)).to be_present
  end

  it 'returns 422 when the knowledge source cap is reached' do
    # Arrange — teto baixo só no teste; 1 fonte knowledge já satura.
    stub_const('Autonomia::Agents::Source::MAX_KNOWLEDGE_SOURCES', 1)
    create_source(agent)

    # Act — nova fonte knowledge estoura o teto.
    post "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/sources",
         params: { source: { source_type: 'txt', reference: 'faq2.txt' } },
         headers: administrator.create_new_auth_token, as: :json

    # Assert — barrado no servidor, nada criado além da fonte inicial.
    expect(response).to have_http_status(:unprocessable_entity)
    expect(agent.sources.knowledge_sources.count).to eq(1)
  end

  it 'rejects a source with an unknown kind with 422 instead of a 500' do
    # Act — kind fora do enum (knowledge|media) cai no guard resolved_kind.
    post "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/sources",
         params: { source: { source_type: 'txt', reference: 'faq.txt' }, kind: 'telepathy' },
         headers: administrator.create_new_auth_token, as: :json

    # Assert
    expect(response).to have_http_status(:unprocessable_entity)
    expect(agent.sources.count).to eq(0)
  end

  # #1426 (revisão adversarial) — dois envios ao mesmo tempo não passam do teto: a contagem e a gravação correm sob a
  # trava da linha do agente (SELECT ... FOR UPDATE antes do INSERT da fonte).
  it 'checks the cap and writes the source under the lock of the agent' do
    # Arrange
    consultas = []
    gravar = ->(*, payload) { consultas << payload[:sql] }

    # Act
    ActiveSupport::Notifications.subscribed(gravar, 'sql.active_record') do
      post "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/sources",
           params: { source: { source_type: 'txt', reference: 'faq.txt' } },
           headers: administrator.create_new_auth_token, as: :json
    end

    # Assert
    expect(response).to have_http_status(:created)
    trava = consultas.index { |sql| sql.include?('FROM "autonomia_agents"') && sql.include?('FOR UPDATE') }
    insercao = consultas.index { |sql| sql.start_with?('INSERT INTO "autonomia_agent_sources"') }
    expect(trava).to be_present
    expect(insercao).to be > trava
  end

  # #1426 (R4) — o 422 chega à tela como está: texto para quem mandou o arquivo, nunca código.
  it 'refuses a file of a kind it cannot read with a plain message' do
    imagem = Rack::Test::UploadedFile.new(Rails.root.join('spec/fixtures/files/autonomia/foto_da_criacao/cardapio-legivel.png'),
                                          'image/png')

    post "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/sources",
         params: { source: { source_type: 'txt', reference: 'cardapio.png' }, file: imagem },
         headers: administrator.create_new_auth_token

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['message']).to eq(I18n.t('autonomia.source.arquivo_tipo'))
    expect(agent.sources.count).to eq(0)
  end
end

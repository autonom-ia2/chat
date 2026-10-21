require 'rails_helper'

# #1427 — quem só vê os agentes (função personalizada com autonomia_view) testa com foto, mas não ensina: a foto do teste
# vale só naquele turno e não cria material, trecho da base nem anexo; "aprender com o arquivo" (POST de sources) é
# escrita e exige autonomia_manage.
RSpec.describe 'Autonomia agent test with a view-only custom role', type: :request do
  let(:account) do
    create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }).tap { |conta| Autonomia::Agents::Fase2.ligar!(conta) }
  end
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'support', status: :active,
                                     instruction: 'Você atende a lanchonete da Bia.')
  end
  let(:png) { Rails.root.join('spec/fixtures/files/autonomia/foto_da_criacao/cardapio-legivel.png').binread }
  let(:cliente_de_ia) do
    instance_double(Crm::Ai::ResponsesClient,
                    create_with_tool_executor: { text: { reply: 'Pela foto, é o X-Salada.', confidence: 0.95, should_handoff: false,
                                                         used_snippet_ids: [], answered_from_knowledge: false }.to_json })
  end
  let(:headers) do
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: ['autonomia_view'])
    user.account_users.find_by(account: account).update!(custom_role: role)
    user.create_new_auth_token
  end

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run }
  end

  before do
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: 'ai-credential'))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente_de_ia)
    allow(Autonomia::Agents::Retriever).to receive(:new)
      .and_return(instance_double(Autonomia::Agents::Retriever, retrieve: []))
  end

  it 'tests with a photo and creates no material, knowledge entry or attachment' do
    contagens = -> { [Autonomia::Agents::Source, Autonomia::Agents::KnowledgeEntry, Attachment].map(&:count) }
    headers
    agent

    expect do
      post "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/test",
           params: { message: 'Quanto custa este?', images: ["data:image/png;base64,#{Base64.strict_encode64(png)}"] },
           headers: headers, as: :json
      expect(response).to have_http_status(:accepted)
      Crm::Ai::InteractiveJob.perform_now(response.parsed_body['id'])
    end.not_to change(contagens, :call)

    pedido = Crm::Ai::InteractiveRequest.read(response.parsed_body['id'])
    expect(pedido['status']).to eq('done')
    expect(pedido.dig('result', 'reply')).to eq('Pela foto, é o X-Salada.')
  end

  it 'cannot teach the agent with the file (POST of sources)' do
    arquivo = Rack::Test::UploadedFile.new(StringIO.new('%PDF-1.4 catálogo'), 'application/pdf', original_filename: 'catalogo.pdf')

    expect do
      post "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/sources",
           params: { source: { source_type: 'pdf', reference: 'catalogo.pdf', kind: 'knowledge' }, file: arquivo }, headers: headers
    end.not_to change(Autonomia::Agents::Source, :count)

    expect(response).to have_http_status(:unauthorized)
  end
end

require 'rails_helper'

# #2487 — o material só de um post ou anúncio (fonte com `care_id`) é gravado com o `autonomia_agent_id` de um agente,
# mas não é do agente: a API de materiais do agente não o lista, não o conta no teto e não o apaga nem relê. Quem cuida
# dele é a tela do post (agentes_do_post/:id/materiais).
RSpec.describe 'Autonomia sources - material do post', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:care) { create(:crm_meta_ads_comment_care, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.')
  end
  let(:url) { "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/sources" }
  let(:headers) { administrator.create_new_auth_token }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  # Aceita, pronta e de conhecimento: só o `care` separa o material do post do material do agente.
  def fonte(reference, care: nil)
    Autonomia::Agents::Source.create!(account: account, agent: agent, care: care, source_type: 'txt', kind: 'knowledge',
                                      status: :ready, review_status: 'accepted', reference: reference)
  end

  it 'index lista só o material do agente' do
    do_agente = fonte('horarios.txt')
    fonte('tamanhos.txt', care: care)

    get url, headers: headers, as: :json

    expect(response.parsed_body['payload'].pluck('id')).to eq([do_agente.id])
  end

  it 'o material do post não conta no teto de materiais do agente', :aggregate_failures do
    stub_const('Autonomia::Agents::Source::MAX_KNOWLEDGE_SOURCES', 1)
    fonte('tamanhos.txt', care: care)

    post url, params: { source: { source_type: 'txt', reference: 'horarios.txt' } }, headers: headers, as: :json
    expect(response).to have_http_status(:created)

    post url, params: { source: { source_type: 'txt', reference: 'precos.txt' } }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'não apaga o material do post pela API do agente; apaga o do agente', :aggregate_failures do
    do_post = fonte('tamanhos.txt', care: care)
    do_agente = fonte('horarios.txt')

    delete "#{url}/#{do_post.id}", headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(Autonomia::Agents::Source.exists?(do_post.id)).to be(true)

    delete "#{url}/#{do_agente.id}", headers: headers, as: :json
    expect(response).to have_http_status(:no_content)
  end

  it 'não relê o material do post pela API do agente' do
    do_post = fonte('tamanhos.txt', care: care)

    expect { post "#{url}/#{do_post.id}/resync", headers: headers, as: :json }
      .not_to have_enqueued_job(Autonomia::Agents::Knowledge::IngestJob)
    expect(response).to have_http_status(:not_found)
  end
end

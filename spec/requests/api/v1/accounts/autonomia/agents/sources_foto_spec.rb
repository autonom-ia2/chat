require 'rails_helper'

# #1426 — o tipo `foto` (a foto da criação como material) só existe na Fase 2. Fora dela, o endpoint de materiais recusa
# com 422 e mensagem clara, sem criar nada.
RSpec.describe 'Autonomia sources - foto', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'support', mode: :guided,
                                     status: :draft, enabled: false, actuation: :external)
  end
  let(:foto) { Rack::Test::UploadedFile.new(StringIO.new('jpg-bytes'), 'image/jpeg', original_filename: 'tabela.jpg') }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  def enviar_foto
    post "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/sources",
         params: { source: { source_type: 'foto', reference: 'tabela.jpg' }, file: foto },
         headers: administrator.create_new_auth_token
  end

  it 'refuses a foto outside the Fase 2 with a clear message and creates nothing' do
    expect { enviar_foto }.not_to change(Autonomia::Agents::Source, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq(I18n.t('autonomia.source.foto_fora_da_fase2'))
  end

  it 'accepts a foto with the Fase 2 and sends it to be read and reviewed' do
    Autonomia::Agents::Fase2.ligar!(account)

    expect { enviar_foto }.to have_enqueued_job(Autonomia::Agents::Knowledge::IngestJob)

    expect(response).to have_http_status(:created)
    expect(agent.sources.sole.source_type).to eq('foto')
  end
end

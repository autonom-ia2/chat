require 'rails_helper'

RSpec.describe 'Autonomia B3 build thread creation contract', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  before do
    allow(Autonomia::Agents::Builder::SubmitJob).to receive(:perform_later)
  end

  it 'creates and links the E1 draft before returning the opening 202' do
    post "/api/v1/accounts/#{account.id}/autonomia/build_threads",
         params: { type: 'sdr', actuation: 'external', with_knowledge: true },
         headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:accepted)
    payload = response.parsed_body.fetch('payload')
    thread = Autonomia::Agents::BuildThread.find(payload.fetch('id'))
    agent = Autonomia::Agents::Agent.find(payload.fetch('agent_id'))

    expect(thread.autonomia_agent_id).to eq(agent.id)
    expect(agent).to be_draft
    expect(agent).to be_guided
    expect(agent).not_to be_enabled
    expect(agent.instruction).to be_blank
    expect(Autonomia::Agents::Builder::SubmitJob).to have_received(:perform_later).with(thread.id, thread.build_token)
  end

  it 'exposes structured knows and suggested links while keeping private builder fields out' do
    thread = Autonomia::Agents::BuildThread.create!(
      account: account,
      created_by: administrator,
      state: {
        'knows' => { 'negocio' => 'serviços', 'publico' => '', 'quando_chama' => '', 'nome' => '' },
        'suggested_links' => ['https://example.test/ajuda'],
        'draft_config' => { 'instruction' => 'segredo' }, 'force_close' => true
      }
    )

    get "/api/v1/accounts/#{account.id}/autonomia/build_threads/#{thread.id}",
        headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    state = response.parsed_body.fetch('payload').fetch('state')
    expect(state.fetch('knows')).to eq(
      'negocio' => 'serviços', 'publico' => '', 'quando_chama' => '', 'nome' => ''
    )
    expect(state.fetch('suggested_links')).to eq(['https://example.test/ajuda'])
    expect(response.body).not_to include('segredo', 'force_close')
  end
end

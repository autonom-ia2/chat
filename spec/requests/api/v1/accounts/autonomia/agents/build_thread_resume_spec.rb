require 'rails_helper'

RSpec.describe 'Autonomia BE-05 build thread resume', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Clara', agent_type: 'custom', mode: :guided, status: :draft,
      enabled: false
    )
  end
  let(:thread) do
    Autonomia::Agents::BuildThread.create!(
      account: account, agent: agent, created_by: administrator, status: :ready,
      build_token: 'token-preservado', messages: [{ 'role' => 'user', 'content' => 'mensagem privada' }],
      state: {
        'force_close' => true, 'needs_more_info' => false, 'next_question' => '', 'turn' => 2,
        'no_materials_declared' => false, 'pending_question' => 'não apagar',
        'materials' => { 'status' => 'ready' }, 'draft_config' => { 'instruction' => 'segredo' }
      }
    )
  end

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  before do
    allow(Autonomia::Agents::Builder::SubmitJob).to receive(:perform_later)
  end

  it 'returns the real latest thread, resets only force_close and does not enqueue work', :aggregate_failures do
    thread
    get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/build_thread",
        headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    payload = response.parsed_body.fetch('payload')
    expect(payload.fetch('id')).to eq(thread.id)
    expect(payload.fetch('messages')).to eq([{ 'role' => 'user', 'content' => 'mensagem privada' }])
    expect(payload.fetch('state')).to include(
      'needs_more_info' => false, 'next_question' => '', 'turn' => 2,
      'no_materials_declared' => false
    )
    expect(response.body).not_to include('segredo', 'force_close', 'token-preservado', 'pending_question')
    expect(thread.reload.state).to include(
      'force_close' => false, 'pending_question' => 'não apagar',
      'materials' => { 'status' => 'ready' }, 'draft_config' => { 'instruction' => 'segredo' }
    )
    unchanged_at = thread.updated_at

    get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/build_thread",
        headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body.dig('payload', 'id')).to eq(thread.id)
    expect(thread.reload.updated_at).to eq(unchanged_at)
    expect(thread.status).to eq('ready')
    expect(thread.build_token).to eq('token-preservado')
    expect(Autonomia::Agents::BuildThread.where(account: account).count).to eq(1)
    expect(Autonomia::Agents::Builder::SubmitJob).not_to have_received(:perform_later)
  end

  it 'chooses the greatest thread id for the same agent and never another agent thread' do
    older = Autonomia::Agents::BuildThread.create!(
      account: account, agent: agent, status: :ready, messages: [{ 'content' => 'antiga' }]
    )
    newer = Autonomia::Agents::BuildThread.create!(
      account: account, agent: agent, status: :ready, messages: [{ 'content' => 'nova' }]
    )
    other_agent = Autonomia::Agents::Agent.create!(
      account: account, name: 'Outra', agent_type: 'custom', mode: :guided, status: :draft, enabled: false
    )
    Autonomia::Agents::BuildThread.create!(
      account: account, agent: other_agent, status: :ready, messages: [{ 'content' => 'alheia' }]
    )
    older.update!(updated_at: Time.current)

    get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/build_thread",
        headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body.dig('payload', 'id')).to eq(newer.id)
    expect(response.body).not_to include('antiga', 'alheia')
    expect(older.reload.id).to be < newer.id
  end

  it 'returns 401 to a viewer before exposing the thread' do
    viewer = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: ['autonomia_view'])
    viewer.account_users.find_by!(account: account).update!(custom_role: role)
    thread

    get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/build_thread",
        headers: viewer.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include('mensagem privada', 'segredo')
  end

  it 'returns 404 for missing, archived and system agents without confirming private data' do
    archived = Autonomia::Agents::Agent.create!(
      account: account, name: 'Arquivado', agent_type: 'custom', mode: :guided, status: :draft, enabled: false
    )
    Autonomia::Agents::BuildThread.create!(
      account: account, agent: archived, messages: [{ 'content' => 'arquivada' }]
    )
    archived.update!(deleted_at: Time.current)
    system_agent = Autonomia::Agents::Agent.create!(
      account: account, name: 'Guia', agent_type: 'custom', mode: :guided, status: :draft, enabled: false,
      config: { 'system_key' => 'guide' }
    )
    Autonomia::Agents::BuildThread.create!(
      account: account, agent: system_agent, messages: [{ 'content' => 'sistema privado' }]
    )

    [archived.id, system_agent.id, agent.id, 9_999_999].each do |agent_id|
      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent_id}/build_thread",
          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include('arquivada', 'sistema privado', 'mensagem privada')
    end
  end

  it 'returns 404 for a thread or agent from another account' do
    other_account = create(:account, internal_attributes: { 'autonomia_agents_enabled' => true })
    foreign_agent = Autonomia::Agents::Agent.create!(
      account: other_account, name: 'Outro', agent_type: 'custom', mode: :guided, status: :draft, enabled: false
    )
    foreign_thread = Autonomia::Agents::BuildThread.create!(
      account: other_account, agent: foreign_agent, messages: [{ 'content' => 'cross tenant' }]
    )

    get "/api/v1/accounts/#{account.id}/autonomia/agents/#{foreign_agent.id}/build_thread",
        headers: administrator.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include('cross tenant')

    get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/build_thread",
        headers: administrator.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    expect(foreign_thread.reload.account_id).to eq(other_account.id)
  end

  it 'returns manual_mode without resetting or enqueuing when the agent is manual' do
    manual = Autonomia::Agents::Agent.create!(
      account: account, name: 'Manual', agent_type: 'custom', mode: :manual, instruction: 'texto escrito',
      status: :draft, enabled: false
    )
    manual_thread = Autonomia::Agents::BuildThread.create!(
      account: account, agent: manual, status: :ready, state: { 'force_close' => true },
      messages: [{ 'role' => 'user', 'content' => 'não perder' }]
    )

    get "/api/v1/accounts/#{account.id}/autonomia/agents/#{manual.id}/build_thread",
        headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('code')).to eq('manual_mode')
    expect(manual_thread.reload.state.fetch('force_close')).to be(true)
    expect(manual_thread.messages).to eq([{ 'role' => 'user', 'content' => 'não perder' }])
    expect(Autonomia::Agents::Builder::SubmitJob).not_to have_received(:perform_later)
  end

  it 'returns instrucao_mantida for Lia without exposing her instruction' do
    lia = Autonomia::Agents::Agent.create!(
      account: account, name: 'Lia', agent_type: 'insurance_quote', mode: :guided,
      instruction: 'instrução privada da Lia', status: :draft, enabled: false
    )
    Autonomia::Agents::BuildThread.create!(account: account, agent: lia, status: :ready)

    get "/api/v1/accounts/#{account.id}/autonomia/agents/#{lia.id}/build_thread",
        headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('code')).to eq('instrucao_mantida')
    expect(response.body).not_to include('instrução privada da Lia')
  end

  it 'rejects a manual message before append, model or enqueue' do
    manual = Autonomia::Agents::Agent.create!(
      account: account, name: 'Manual', agent_type: 'custom', mode: :manual, instruction: 'texto escrito',
      status: :draft, enabled: false
    )
    manual_thread = Autonomia::Agents::BuildThread.create!(
      account: account, agent: manual, status: :open, state: { 'force_close' => true },
      messages: [{ 'role' => 'assistant', 'content' => 'histórico' }]
    )

    post "/api/v1/accounts/#{account.id}/autonomia/build_threads/#{manual_thread.id}/messages",
         params: { message: 'não sobrescrever' }, headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('code')).to eq('manual_mode')
    expect(manual_thread.reload.messages).to eq([{ 'role' => 'assistant', 'content' => 'histórico' }])
    expect(manual_thread.status).to eq('open')
    expect(manual_thread.state.fetch('force_close')).to be(true)
    expect(Autonomia::Agents::Builder::SubmitJob).not_to have_received(:perform_later)
  end

  it 'keeps the existing Lia guard before a message can reach the Builder' do
    lia = Autonomia::Agents::Agent.create!(
      account: account, name: 'Lia', agent_type: 'insurance_quote', mode: :guided,
      instruction: 'instrução privada', status: :draft, enabled: false
    )
    lia_thread = Autonomia::Agents::BuildThread.create!(account: account, agent: lia, status: :open)

    post "/api/v1/accounts/#{account.id}/autonomia/build_threads/#{lia_thread.id}/messages",
         params: { message: 'não editar Lia' }, headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('code')).to eq('instrucao_mantida')
    expect(lia_thread.reload.messages).to be_empty
    expect(Autonomia::Agents::Builder::SubmitJob).not_to have_received(:perform_later)
  end
end

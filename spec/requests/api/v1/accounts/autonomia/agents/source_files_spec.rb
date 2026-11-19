require 'rails_helper'

RSpec.describe 'Agent source original files', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'support', mode: :guided,
                                     status: :draft, enabled: false, actuation: :external)
  end
  let(:source) do
    agent.sources.create!(account: account, source_type: 'pdf', reference: 'guide.pdf', status: :ready, review_status: 'accepted')
  end
  let(:headers) { administrator.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/sources/#{source.id}/file" }
  let(:storage) { ActiveStorage::Blob.service }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run }
  end

  before do
    source.file.attach(io: Rails.root.join('spec/assets/sample.pdf').open, filename: 'guide.pdf', content_type: 'application/pdf')
    allow(storage).to receive(:url).and_return('https://files.example.org/guide.pdf?signature=temporary')
    allow(storage).to receive(:exist?).and_return(true)
  end

  it 'returns a short-lived link without loading the original file into Rails memory', :aggregate_failures do
    expect(storage).not_to receive(:download)

    get url, headers: headers

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('url' => 'https://files.example.org/guide.pdf?signature=temporary')
    expect(response.headers['Cache-Control']).to include('private', 'no-store')
    expect(storage).to have_received(:url).with(anything, hash_including(expires_in: 1.minute, disposition: :inline))
  end

  it 'offers the original attachment in the source list without a signed URL', :aggregate_failures do
    missing = agent.sources.create!(account: account, source_type: 'txt', reference: 'legacy.txt')

    get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/sources", headers: headers

    expect(response).to have_http_status(:ok)
    items = response.parsed_body.fetch('payload').index_by { |item| item['id'] }
    expect(items.fetch(source.id)['file_attached']).to be(true)
    expect(items.fetch(missing.id)['file_attached']).to be(false)
    expect(response.body).not_to include('signature=temporary')
    expect(storage).not_to have_received(:url)
  end

  it 'requires authentication' do
    get url

    expect(response).to have_http_status(:unauthorized)
    expect(storage).not_to have_received(:url)
  end

  it 'rejects an ordinary account agent without the module permission' do
    user = create(:user, account: account, role: :agent)

    get url, headers: user.create_new_auth_token

    expect(response).to have_http_status(:unauthorized)
    expect(storage).not_to have_received(:url)
  end

  it 'cannot use the endpoint after the module is disabled' do
    account.update!(internal_attributes: { 'autonomia_agents_enabled' => false })

    get url, headers: headers

    expect(response).to have_http_status(:not_found)
  end

  it 'does not find a source under another agent' do
    other_agent = agent.dup
    other_agent.update!(name: 'Outro agente')

    get url.sub("agents/#{agent.id}/", "agents/#{other_agent.id}/"), headers: headers

    expect(response).to have_http_status(:not_found)
    expect(storage).not_to have_received(:url)
  end

  it 'returns 404 when the source has no original attachment' do
    source.file.detach

    get url, headers: headers

    expect(response).to have_http_status(:not_found)
    expect(storage).not_to have_received(:url)
  end

  it 'returns 404 when the stored object is missing' do
    allow(storage).to receive(:exist?).and_return(false)

    get url, headers: headers

    expect(response).to have_http_status(:not_found)
    expect(storage).not_to have_received(:url)
  end

  it 'does not find an agent or file belonging to another account' do
    other_account = create(:account)
    other_agent = Autonomia::Agents::Agent.create!(account: other_account, name: 'Outro', agent_type: 'support', status: :draft)

    get url.sub("agents/#{agent.id}/", "agents/#{other_agent.id}/"), headers: headers

    expect(response).to have_http_status(:not_found)
    expect(storage).not_to have_received(:url)
  end

  it 'does not expose material that belongs to a post rather than the agent' do
    source.update!(care: create(:crm_meta_ads_comment_care, account: account))

    get url, headers: headers

    expect(response).to have_http_status(:not_found)
    expect(storage).not_to have_received(:url)
  end

  it 'does not expose files of a discarded agent' do
    agent.update!(deleted_at: Time.current)

    get url, headers: headers

    expect(response).to have_http_status(:not_found)
  end

  it 'does not expose files of a system agent' do
    agent.update!(config: { system_key: 'internal' })

    get url, headers: headers

    expect(response).to have_http_status(:not_found)
  end

  it 'returns not found for a missing original attachment' do
    source.file.purge

    get url, headers: headers

    expect(response).to have_http_status(:not_found)
    expect(storage).not_to have_received(:url)
  end

  it 'downloads non-previewable documents' do
    source.file.attach(io: StringIO.new('Example'), filename: 'original.docx',
                       content_type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', identify: false)

    get url, headers: headers

    expect(response).to have_http_status(:ok)
    expect(storage).to have_received(:url).with(anything, hash_including(disposition: :attachment))
  end

  it 'keeps signed file links out of the Guide catalog' do
    action = 'GET autonomia/agents/:agent_id/sources/:source_id/file'

    expect(Autonomia::Guide::Acoes.fora_do_catalogo?(action)).to be(true)
    expect(Autonomia::Guide::Acoes.so_na_tela(action)).to eq(I18n.t('autonomia.guide.only_on_screen.agent_source_file'))
  end
end

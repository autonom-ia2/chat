require 'rails_helper'

RSpec.describe 'Autonomia reusable knowledge sources', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:headers) { administrator.create_new_auth_token }
  let(:target) { Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'support', mode: :guided) }
  let(:origin) { Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'support', mode: :guided) }
  let!(:source) do
    Autonomia::Agents::Source.create!(account: account, agent: origin, source_type: 'txt', reference: 'respostas.txt',
                                     status: :ready, review_status: 'accepted')
  end
  let(:endpoint) { "/api/v1/accounts/#{account.id}/autonomia/agents/#{target.id}/sources" }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  it 'lists only ready accepted knowledge from other kept non-system agents' do
    own = target.sources.create!(account: account, source_type: 'txt', reference: 'proprio.txt', status: :ready, review_status: 'accepted')
    pending = origin.sources.create!(account: account, source_type: 'txt', reference: 'pendente.txt')
    media = origin.sources.create!(account: account, source_type: 'txt', reference: 'midia.txt', kind: :media,
                                   status: :ready, review_status: 'accepted')
    archived = Autonomia::Agents::Agent.create!(account: account, name: 'Arquivado', agent_type: 'support', deleted_at: Time.current)
    archived_source = archived.sources.create!(account: account, source_type: 'txt', reference: 'arquivado.txt',
                                               status: :ready, review_status: 'accepted')
    faq = origin.sources.create!(account: account, source_type: 'txt', reference: 'faq.txt', status: :ready, review_status: 'accepted',
                                 metadata: { 'faq_suggestions' => true })

    get "#{endpoint}/reusable", headers: headers

    expect(response).to have_http_status(:ok)
    ids = response.parsed_body.fetch('payload').pluck('id')
    expect(ids).to include(source.id)
    expect(ids).not_to include(own.id, pending.id, media.id, archived_source.id, faq.id)
  end

  it 'copies the attachment without duplicating its blob and enqueues ingestion' do
    source.file.attach(io: StringIO.new('Respostas de exemplo'), filename: 'respostas.txt', content_type: 'text/plain')

    expect do
      post "#{endpoint}/copy", params: { source_id: source.id }, headers: headers, as: :json
    end.to have_enqueued_job(Autonomia::Agents::Knowledge::IngestJob)

    expect(response).to have_http_status(:created)
    copied = target.sources.last
    expect(copied.file.blob_id).to eq(source.file.blob_id)
    expect(copied.account_id).to eq(account.id)
    expect(copied.metadata['copied_from_source_id']).to eq(source.id)
    expect(copied.review_status).to be_nil
    expect(copied.status).to eq('pending')
    expect(source.reload.agent).to eq(origin)
  end

  it 'refuses a source from another account without creating anything' do
    foreign_account = create(:account)
    foreign = Autonomia::Agents::Agent.create!(account: foreign_account, name: 'Outra conta', agent_type: 'support')
    foreign_source = foreign.sources.create!(account: foreign_account, source_type: 'txt', reference: 'outro.txt',
                                             status: :ready, review_status: 'accepted')

    expect do
      post "#{endpoint}/copy", params: { source_id: foreign_source.id }, headers: headers, as: :json
    end.not_to change(target.sources, :count)
    expect(response).to have_http_status(:not_found)
  end

  it 'refuses a pending source instead of treating it as learned material' do
    source.update!(status: :processing)

    expect do
      post "#{endpoint}/copy", params: { source_id: source.id }, headers: headers, as: :json
    end.not_to change(target.sources, :count)
    expect(response).to have_http_status(:not_found)
  end

  it 'respects the knowledge limit without enqueueing ingestion' do
    stub_const('Autonomia::Agents::Source::MAX_KNOWLEDGE_SOURCES', 1)
    target.sources.create!(account: account, source_type: 'txt', reference: 'ja-tem.txt')

    expect do
      post "#{endpoint}/copy", params: { source_id: source.id }, headers: headers, as: :json
    end.not_to have_enqueued_job(Autonomia::Agents::Knowledge::IngestJob)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(target.sources.count).to eq(1)
  end

  it 'rejects malformed source ids at the request boundary' do
    post "#{endpoint}/copy", params: { source_id: { value: source.id } }, headers: headers, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('invalid_source_id')
    expect(target.sources.count).to eq(0)
  end

  it 'does not copy a material for someone who can only view agents' do
    viewer = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: ['autonomia_view'])
    account.account_users.find_by!(user: viewer).update!(custom_role: role)

    post "#{endpoint}/copy", params: { source_id: source.id }, headers: viewer.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(target.sources.count).to eq(0)
  end
end

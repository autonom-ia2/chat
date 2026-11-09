require 'rails_helper'

# #2775, revisão item 15: as listas da Prospecção pedem prospecting_manage e campaign_manage. Uma função personalizada
# (EE) com as duas chaves abre, tira, devolve e copia, como o administrador.
RSpec.describe 'Listas da Prospecção com função personalizada (#2775)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:base) { "/api/v1/accounts/#{account.id}/autonomia/prospecting" }
  let(:audiences_on) { { 'CAMPAIGN_JOURNEY_ENABLED' => 'true', 'CAMPAIGN_IMPORT_ENABLED' => 'true' } }
  let(:gestora) do
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}",
                              permissions: %w[prospecting_view prospecting_manage campaign_manage])
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    user
  end

  before { Autonomia::Prospecting::Config.enable_for!(account) }

  def call(verb, path, user:, params: {})
    with_modified_env(audiences_on) { public_send(verb, "#{base}#{path}", params: params, headers: user.create_new_auth_token, as: :json) }
  end

  it 'com campaign_manage: lista, abre, tira, devolve e copia' do
    lead = Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: 'ee-lists-1', name: 'Empresa',
                                                phone: '+55 31 99999-4300', country: 'BR')
    call(:post, '/leads/audience', user: admin, params: { lead_ids: [lead.id], name: 'Padarias' })
    list_id = response.parsed_body.dig('payload', 'audience', 'id')
    contact_id = lead.reload.contact_id

    call(:get, '/audiences', user: gestora)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload'].pluck('id')).to eq([list_id])

    call(:get, "/audiences/#{list_id}", user: gestora)
    expect(response).to have_http_status(:ok)

    call(:delete, "/audiences/#{list_id}/members", user: gestora, params: { contact_ids: [contact_id] })
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'removed_contact_ids')).to eq([contact_id])

    call(:post, "/audiences/#{list_id}/members", user: gestora, params: { contact_ids: [contact_id] })
    expect(response).to have_http_status(:ok)

    call(:post, "/audiences/#{list_id}/copy", user: gestora)
    expect(response).to have_http_status(:created)
  end
end

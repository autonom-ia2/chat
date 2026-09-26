require 'rails_helper'

# Jogadas salvas (#732, MODO-25, MODO-26, FILTRO-27, PLAT-17): quem gerencia a prospecção salva, edita e exclui; quem só
# vê recebe a lista nas configurações para usar na grade. Tudo por conta.
RSpec.describe 'Autonomia prospecting saved presets API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:base_path) { "/api/v1/accounts/#{account.id}/autonomia/prospecting" }
  let(:presets_path) { "#{base_path}/saved_presets" }

  before { Autonomia::Prospecting::Config.enable_for!(account) }

  def agent_with(permissions)
    agent = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    agent.account_users.find_by(account: account).update!(custom_role: role)
    agent
  end

  def create_preset(user, saved_preset)
    post presets_path, params: { saved_preset: saved_preset }, headers: auth_headers(user), as: :json
  end

  def existing_preset(target_account = account, name: 'Sem site')
    Autonomia::Prospecting::SavedPreset.create!(account: target_account, name: name, score_mode: 'gbp', filters: { 'has_website' => 'no' })
  end

  it 'salva os filtros atuais como jogada da conta e devolve o id que a busca usa' do
    create_preset(admin, name: ' Sem site e com telefone ', score_mode: 'gbp',
                         filters: { has_website: 'no', has_phone: 'yes', rating_min: '', reviews_min: '10' })

    expect(response).to have_http_status(:created)
    preset = Autonomia::Prospecting::SavedPreset.last
    expect(response.parsed_body['payload']).to include(
      'id' => preset.id, 'preset_id' => "saved-#{preset.id}", 'name' => 'Sem site e com telefone', 'score_mode' => 'gbp',
      'filters' => { 'has_website' => 'no', 'has_phone' => 'yes', 'reviews_min' => 10 }
    )
    expect(preset.account).to eq(account)
    expect(preset.user).to eq(admin)
  end

  it 'recusa filtro fora da gaveta com a frase em português, sem gravar' do
    create_preset(admin, name: 'Estranha', score_mode: 'gbp', filters: { has_website: 'no', sql: 'drop' })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq(I18n.t('autonomia.prospecting.saved_presets.errors.invalid_filters'))
    expect(Autonomia::Prospecting::SavedPreset.count).to eq(0)
  end

  it 'para no limite de jogadas da conta' do
    stub_const('Autonomia::Prospecting::SavedPreset::MAX_PER_ACCOUNT', 1)
    existing_preset

    create_preset(admin, name: 'Outra', score_mode: 'gbp', filters: { has_phone: 'yes' })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq(I18n.t('autonomia.prospecting.saved_presets.errors.limit', max: 1))
  end

  it 'as configurações entregam as jogadas da conta, mais nova primeiro, para quem só vê' do
    older = existing_preset(name: 'Antiga')
    newer = existing_preset(name: 'Nova')
    existing_preset(create(:account), name: 'De outra conta')

    get "#{base_path}/settings", headers: auth_headers(agent_with(['prospecting_view']))

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'saved_presets').pluck('id')).to eq([newer.id, older.id])
  end

  it 'edita nome e filtros, sem trocar o modo' do
    preset = existing_preset

    patch "#{presets_path}/#{preset.id}", params: { saved_preset: { name: 'Com telefone', score_mode: 'general', filters: { has_phone: 'yes' } } },
                                          headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:ok)
    expect(preset.reload.slice(:name, :score_mode, :filters))
      .to eq('name' => 'Com telefone', 'score_mode' => 'gbp', 'filters' => { 'has_phone' => 'yes' })
  end

  it 'edição inválida não muda a jogada' do
    preset = existing_preset

    patch "#{presets_path}/#{preset.id}", params: { saved_preset: { filters: { rating_min: 9 } } }, headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(preset.reload.filters).to eq('has_website' => 'no')
  end

  it 'exclui a jogada' do
    preset = existing_preset

    delete "#{presets_path}/#{preset.id}", headers: auth_headers(admin)

    expect(response).to have_http_status(:no_content)
    expect(Autonomia::Prospecting::SavedPreset.exists?(preset.id)).to be(false)
  end

  it 'não enxerga jogada de outra conta' do
    foreign = existing_preset(create(:account))

    patch "#{presets_path}/#{foreign.id}", params: { saved_preset: { name: 'Minha' } }, headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:not_found)

    delete "#{presets_path}/#{foreign.id}", headers: auth_headers(admin)
    expect(response).to have_http_status(:not_found)
    expect(foreign.reload.name).to eq('Sem site')
  end

  it 'quem só vê a prospecção não salva, não edita nem exclui' do
    viewer = agent_with(['prospecting_view'])
    preset = existing_preset

    create_preset(viewer, name: 'Minha', score_mode: 'gbp', filters: { has_phone: 'yes' })
    expect(response).to have_http_status(:unauthorized)

    patch "#{presets_path}/#{preset.id}", params: { saved_preset: { name: 'Minha' } }, headers: auth_headers(viewer), as: :json
    expect(response).to have_http_status(:unauthorized)

    delete "#{presets_path}/#{preset.id}", headers: auth_headers(viewer)
    expect(response).to have_http_status(:unauthorized)
    expect(preset.reload.name).to eq('Sem site')
  end

  it 'quem gerencia a prospecção salva' do
    create_preset(agent_with(['prospecting_manage']), name: 'Minha', score_mode: 'general', filters: { has_phone: 'yes' })

    expect(response).to have_http_status(:created)
  end
end

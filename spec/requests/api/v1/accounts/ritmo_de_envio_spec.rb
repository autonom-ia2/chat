require 'rails_helper'

# #3063, item 2: a tela "Limite de mensagens" lê e grava o ritmo de envio da conta.
RSpec.describe 'Ritmo de envio API (#3063)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:path) { "/api/v1/accounts/#{account.id}/ritmo_de_envio" }

  def headers(user = admin) = { 'api_access_token' => user.access_token.token }

  def user_with(permissions)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    user
  end

  it 'começa sem limite e a qualquer hora' do
    get path, headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload']).to include('limite' => nil, 'intervalo' => nil, 'horario' => nil)
  end

  it 'grava e devolve o intervalo entre mensagens sem apagar o limite (#3101)' do
    patch path, headers: headers, as: :json, params: { limite: { mensagens: 3, dias: 7 } }
    patch path, headers: headers, as: :json, params: { intervalo: { horas: 4 } }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload']).to include('limite' => { 'mensagens' => 3, 'dias' => 7 }, 'intervalo' => { 'horas' => 4 })
    expect(Autonomia::RitmoDeEnvio::Config.da(account.reload).intervalo).to eq('horas' => 4)

    get path, headers: headers, as: :json
    expect(response.parsed_body['payload']['intervalo']).to eq('horas' => 4)

    patch path, headers: headers, as: :json, params: { intervalo: nil }
    expect(response.parsed_body['payload']['intervalo']).to be_nil
  end

  it 'recusa intervalo que a tela não oferece' do
    patch path, headers: headers, as: :json, params: { intervalo: { horas: 3 } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('parameter' => 'intervalo.horas')
  end

  it 'grava o limite e o horário sem mexer nas outras configurações da conta' do
    account.update_columns(settings: account.settings.to_h.merge('auto_resolve_after' => 90)) # rubocop:disable Rails/SkipsModelValidations

    patch path, headers: headers, as: :json,
                params: { limite: { mensagens: 3, dias: 7 }, horario: { inicio: 8, fim: 20, dias_da_semana: [1, 2, 3, 4, 5] } }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload']).to include('limite' => { 'mensagens' => 3, 'dias' => 7 },
                                                       'horario' => { 'inicio' => 8, 'fim' => 20, 'dias_da_semana' => [1, 2, 3, 4, 5] })
    settings = account.reload.settings
    expect(settings['auto_resolve_after']).to eq(90)
    expect(Autonomia::RitmoDeEnvio::Config.da(account).limite).to eq('mensagens' => 3, 'dias' => 7)
  end

  it 'volta a sem limite e a qualquer hora' do
    patch path, headers: headers, as: :json, params: { limite: { mensagens: 3, dias: 7 } }
    patch path, headers: headers, as: :json, params: { limite: nil, horario: nil }

    expect(response.parsed_body['payload']).to include('limite' => nil, 'horario' => nil)
  end

  it 'mandar só uma das chaves não apaga a outra' do
    patch path, headers: headers, as: :json,
                params: { limite: { mensagens: 3, dias: 7 }, horario: { inicio: 8, fim: 20, dias_da_semana: [1] } }
    patch path, headers: headers, as: :json, params: { limite: { mensagens: 5, dias: 15 } }

    expect(response.parsed_body['payload']).to include('limite' => { 'mensagens' => 5, 'dias' => 15 },
                                                       'horario' => { 'inicio' => 8, 'fim' => 20, 'dias_da_semana' => [1] })
  end

  it 'recusa o que a tela não oferece, dizendo o campo' do
    patch path, headers: headers, as: :json, params: { horario: { inicio: 20, fim: 8, dias_da_semana: [1] } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('error' => 'ritmo_de_envio.invalido', 'parameter' => 'horario.fim')
  end

  it 'quem vê campanhas lê; só quem cuida delas grava' do
    leitor = user_with(%w[campaign_view])

    get path, headers: headers(leitor), as: :json
    expect(response).to have_http_status(:ok)

    patch path, headers: headers(leitor), as: :json, params: { limite: { mensagens: 1, dias: 1 } }
    expect(response).to have_http_status(:unauthorized)
    expect(Autonomia::RitmoDeEnvio::Config.da(account.reload).limite).to be_nil

    patch path, headers: headers(user_with(%w[campaign_view campaign_manage])), as: :json, params: { limite: { mensagens: 1, dias: 1 } }
    expect(response).to have_http_status(:ok)
  end

  it 'agente sem função não vê' do
    agente = create(:user, account: account, role: :agent)

    get path, headers: headers(agente), as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end

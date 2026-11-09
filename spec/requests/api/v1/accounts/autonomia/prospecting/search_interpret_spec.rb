require 'rails_helper'

# Pedido em uma frase (#2696, F4): POST searches/interpret { frase } devolve "O quê?", "Onde?" e os ajustes que a IA da
# conta entendeu, para a pessoa conferir. Não cria busca. Pede prospecting_manage, como criar a busca.
RSpec.describe 'Autonomia prospecting search interpret', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:path) { "/api/v1/accounts/#{account.id}/autonomia/prospecting/searches/interpret" }
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:blank_answer) do
    { 'understood' => true, 'what' => nil, 'where' => nil, 'rating_min' => nil, 'rating_max' => nil, 'reviews_min' => nil,
      'has_website' => nil, 'has_photos' => nil, 'open_now' => nil, 'has_opening_hours' => nil, 'weak_presence' => false,
      'left_out' => nil }
  end

  before do
    Autonomia::Prospecting::Config.enable_for!(account)
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-da-conta' })
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
  end

  def agent_with(permissions)
    agent = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    agent.account_users.find_by(account: account).update!(custom_role: role)
    agent
  end

  def answer_with(fields)
    allow(client).to receive(:create).and_return({ text: blank_answer.merge(fields).to_json, usage: {} })
  end

  def interpret(text = 'padarias perto da Paulista com nota boa', user: admin)
    post path, params: { frase: text }, headers: auth_headers(user), as: :json
  end

  it 'devolve os campos que a IA entendeu e não cria busca' do
    answer_with('what' => 'padarias', 'where' => 'Avenida Paulista, São Paulo', 'rating_min' => '4', 'weak_presence' => true)

    expect { interpret }.not_to change(Autonomia::Prospecting::Search, :count)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload']).to eq(
      'status' => 'understood', 'what' => 'padarias', 'where' => 'Avenida Paulista, São Paulo',
      'advanced_filters' => { 'rating_min' => '4' }, 'score_mode' => 'gbp', 'left_out' => nil
    )
  end

  it 'descarta o valor fora do conjunto da tela' do
    answer_with('what' => 'academias', 'rating_min' => '5', 'reviews_min' => '20', 'has_website' => 'talvez')

    interpret

    expect(response.parsed_body.dig('payload', 'advanced_filters')).to eq('reviews_min' => '20')
  end

  it '"não entendi" volta como desfecho, com os campos vazios' do
    answer_with('understood' => false)

    interpret('bom dia, tudo bem?')

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload']).to include('status' => 'not_understood', 'what' => nil, 'where' => nil)
  end

  it 'erro da IA vira resposta tratada, com código e frase para leigo' do
    allow(client).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error.new('boom', status: 500))

    interpret

    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body).to eq('code' => 'prospecting.interpret.ai_failed',
                                       'error' => I18n.t('autonomia.prospecting.interpret.errors.ai_failed'))
  end

  it 'conta sem a IA ligada responde ai_not_configured' do
    account.hooks.destroy_all

    interpret

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('prospecting.interpret.ai_not_configured')
  end

  # O gate da Prospecção (check_module_permission!) levanta Pundit::NotAuthorizedError, que o painel responde com 401,
  # como o exportar (#2147).
  it 'só com prospecting_view: recusado pelo gate, sem chamar a IA' do
    interpret(user: agent_with(%w[prospecting_view]))

    expect(response).to have_http_status(:unauthorized)
    expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
  end

  it 'com prospecting_manage, o agente pede' do
    answer_with('what' => 'oficinas')

    interpret(user: agent_with(%w[prospecting_view prospecting_manage]))

    expect(response).to have_http_status(:ok)
  end

  it 'prospecção desligada na conta: 404' do
    Autonomia::Prospecting::Config.disable_for!(account)

    interpret

    expect(response).to have_http_status(:not_found)
  end
end

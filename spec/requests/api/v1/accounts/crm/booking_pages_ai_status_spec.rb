require 'rails_helper'

# Contrato da lista de páginas para a gaveta do agente de IA (#1305): `ai_status`, `recebe` e `timezone` em cada
# página, com a elegibilidade de quem atende lida uma vez para a lista inteira.
RSpec.describe 'Api::V1::Accounts::Crm::BookingPages ai_status', type: :request do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:world) { build_booking_world(account: account) }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true') { example.run }
  end

  before { account.enable_features!('crm_booking_v2') }

  def index_queries_on_account_users
    contadas = []
    contar = ->(*, payload) { contadas << payload[:sql] if payload[:sql].include?('FROM "account_users"') }
    ActiveSupport::Notifications.subscribed(contar, 'sql.active_record') do
      get "/api/v1/accounts/#{account.id}/crm/booking_pages", headers: admin.create_new_auth_token, as: :json
    end
    contadas.size
  end

  it 'devolve o estado da IA, quem recebe e o fuso de cada página' do
    world.host.update!(display_name: 'Cami')
    pausada = create_booking_profile(account: account, host: world.host, pipeline: world.pipeline, stage: world.stage, enabled: false)

    get "/api/v1/accounts/#{account.id}/crm/booking_pages", headers: admin.create_new_auth_token, as: :json

    paginas = response.parsed_body['payload'].index_by { |page| page['id'] }
    expect(paginas[world.profile.id]).to include('ai_status' => 'ativa', 'recebe' => { 'modo' => 'fixo', 'nome' => 'Cami' },
                                                 'timezone' => 'America/Sao_Paulo')
    expect(paginas[pausada.id]).to include('ai_status' => 'pausada')
  end

  it 'mais páginas não fazem mais consultas de quem pode atender por página' do
    world
    uma = index_queries_on_account_users
    3.times { create_booking_profile(account: account, host: world.host, pipeline: world.pipeline, stage: world.stage) }

    expect(index_queries_on_account_users).to eq(uma)
  end
end

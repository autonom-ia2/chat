require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Crm::MemoriaConfig', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:robo) { create(:user, account: account, name: 'Ana Maciel') }
  let(:caminho) { "/api/v1/accounts/#{account.id}/crm/memoria/config" }

  before { allow(Crm::Config).to receive(:enabled?).and_return(true) }

  it 'sem a flag é 404' do
    get caminho, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end

  context 'with the flag on' do
    before { ligar_memoria!(account) }

    it 'o administrador declara os robôs e as caixas fora da memória' do
      inbox = create(:inbox, account: account)
      put caminho, headers: admin.create_new_auth_token, params: { usuarios_robo_ids: [robo.id], caixas_excluidas: [inbox.id] }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('usuarios_robo_ids' => [robo.id], 'caixas_excluidas' => [inbox.id])
      get caminho, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['usuarios_robo_ids']).to eq([robo.id])
    end

    it 'recusa usuário de outra conta e quem não é administrador' do
      put caminho, headers: admin.create_new_auth_token, params: { usuarios_robo_ids: [create(:user).id] }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      put caminho, headers: admin.create_new_auth_token, params: { usuarios_robo_ids: robo.id }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      get caminho, headers: agente.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end
end

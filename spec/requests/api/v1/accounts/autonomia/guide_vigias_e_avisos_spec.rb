require 'rails_helper'

# Vigias e avisos do Guia (#935): só administrador; cada pessoa vê só os avisos dela (AC-I7).
RSpec.describe 'Guia da Plataforma — vigias e avisos', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:outro_admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:vigias) { "/api/v1/accounts/#{account.id}/autonomia/vigias" }
  let(:avisos) { "/api/v1/accounts/#{account.id}/autonomia/avisos" }
  let(:corpo) do
    { nome: 'Conexão caída', gravidade: 'urgente',
      leitura: { rota: 'inboxes', medida: { tipo: 'contagem', onde: { reauthorization_required: true } } },
      gatilho: { acima_de: 0 } }
  end

  before { allow(Autonomia::Guide::Seed).to receive(:eligible?).and_return(true) }

  def aviso!(user, estado: 'novo')
    Autonomia::Guide::Aviso.create!(account: account, user: user, chave: SecureRandom.hex, estado: estado,
                                    texto: 'Conexão caída: 1 agora.', sinal: { 'sinais' => [{ 'vigia_id' => 1, 'valor' => 1 }] })
  end

  describe 'vigias' do
    it 'o administrador cria, lê, ajusta e apaga', :aggregate_failures do
      post vigias, params: corpo, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)
      vigia = Autonomia::Guide::Vigia.last
      expect(vigia).to have_attributes(account_id: account.id, criado_por_id: admin.id, nome: 'Conexão caída', origem: 'pessoa')
      expect(vigia.leitura).to eq('rota' => 'inboxes', 'medida' => { 'tipo' => 'contagem', 'onde' => { 'reauthorization_required' => true } })

      get vigias, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['vigias'].pluck('id')).to eq([vigia.id])

      patch "#{vigias}/#{vigia.id}", params: { ativa: false }, headers: admin.create_new_auth_token, as: :json
      expect(vigia.reload.ativa).to be(false)

      delete "#{vigias}/#{vigia.id}", headers: admin.create_new_auth_token, as: :json
      expect(Autonomia::Guide::Vigia.exists?(vigia.id)).to be(false)
    end

    it 'recusa leitura que não é da conta e gatilho sem número', :aggregate_failures do
      post vigias, params: corpo.merge(leitura: { rota: 'nao/existe', medida: { tipo: 'contagem' } }),
                   headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('nao/existe')

      post vigias, params: corpo.merge(gatilho: {}), headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'soma e maior precisam do campo' do
      post vigias, params: corpo.merge(leitura: { rota: 'automation_rules', medida: { tipo: 'maior' } }),
                   headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['error']).to include('Campo is required')
    end

    # AC-I4: no máximo 20 vigias por conta.
    it 'não passa de 20 vigias por conta', :aggregate_failures do
      20.times { |indice| Autonomia::Guide::Vigia.create!(corpo.deep_stringify_keys.merge('account' => account, 'nome' => "v#{indice}")) }

      post vigias, params: corpo, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Autonomia::Guide::Vigia.where(account: account).count).to eq(20)
    end

    it 'agente comum não lê nem cria', :aggregate_failures do
      get vigias, headers: agente.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      post vigias, params: corpo, headers: agente.create_new_auth_token, as: :json
      expect(Autonomia::Guide::Vigia.count).to eq(0)
    end

    it 'vigia de outra conta é 404' do
      outra = create(:account)
      vigia = Autonomia::Guide::Vigia.create!(corpo.deep_stringify_keys.merge('account' => outra))

      get "#{vigias}/#{vigia.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'conta sem o Guia não tem vigia nenhuma' do
      allow(Autonomia::Guide::Seed).to receive(:eligible?).and_return(false)

      get vigias, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'avisos' do
    it 'lista só os da pessoa, filtra por estado e conta os novos', :aggregate_failures do
      novo = aviso!(admin)
      aviso!(admin, estado: 'visto')
      aviso!(outro_admin)

      get avisos, params: { estado: 'novo' }, headers: admin.create_new_auth_token

      expect(response.parsed_body['avisos'].pluck('id')).to eq([novo.id])
      expect(response.parsed_body['novos']).to eq(1)
    end

    it 'marca como visto' do
      aviso = aviso!(admin)

      patch "#{avisos}/#{aviso.id}", params: { estado: 'visto' }, headers: admin.create_new_auth_token, as: :json

      expect(aviso.reload.estado).to eq('visto')
    end

    it 'aviso de outra pessoa é 404, igual a um que não existe', :aggregate_failures do
      dele = aviso!(outro_admin)

      patch "#{avisos}/#{dele.id}", params: { estado: 'visto' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(dele.reload.estado).to eq('novo')
    end

    it 'só aceita novo ou visto', :aggregate_failures do
      aviso = aviso!(admin)

      patch "#{avisos}/#{aviso.id}", params: { estado: 'resumido' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(aviso.reload.estado).to eq('novo')
    end

    it 'agente comum não recebe aviso' do
      get avisos, headers: agente.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end
  end
end

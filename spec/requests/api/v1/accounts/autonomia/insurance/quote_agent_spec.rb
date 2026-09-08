require 'rails_helper'

# A PORTA DO AGENTE DE COTAÇÃO.
#
# Um agente que fala com cliente e carrega credencial de portal não se cria por acidente: o gate do
# módulo (feature ligada, conta marcada, administrador) vale aqui igual ao da conexão.
RSpec.describe 'Autonomia Insurance Quote Agent API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:atendente) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/autonomia/insurance/quote_agent" }
  let(:dados) do
    { quote_agent: { name: 'Mia', broker_name: 'Corretora Exemplo',
                     business_hours: 'de segunda a sexta, das 09h às 18h', behavior: 'consultivo' } }
  end

  def enable_feature!(enabled: true)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('INSURANCE_QUOTING_ENABLED', false).and_return(enabled ? 'true' : 'false')
    Autonomia::Insurance::Config.enable_for!(account) if enabled
  end

  before { enable_test_encryption! }

  describe 'gate e permissão' do
    it 'esconde o recurso quando a feature esta desligada' do
      enable_feature!(enabled: false)
      post base, params: dados, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(Autonomia::Agents::Agent.count).to eq(0)
    end

    it 'recusa atendente comum' do
      enable_feature!
      post base, params: dados, headers: atendente.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(Autonomia::Agents::Agent.count).to eq(0)
    end
  end

  describe 'GET' do
    before { enable_feature! }

    # `null` é a resposta que faz a tela oferecer "criar" em vez de "abrir".
    it 'responde vazio quando ainda nao existe' do
      get base, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to be_nil
    end

    it 'responde o agente e os ramos que ele cota' do
      post base, params: dados, headers: admin.create_new_auth_token, as: :json
      get base, headers: admin.create_new_auth_token, as: :json

      payload = response.parsed_body['payload']
      expect(payload['name']).to eq('Mia')
      expect(payload['agent_type']).to eq('insurance_quote')
      expect(payload['specialists'].map { |s| s['slug'] }).to eq(['cotacao_auto'])
    end
  end

  describe 'POST' do
    before { enable_feature! }

    it 'cria o agente pronto, com o especialista' do
      # Act
      post base, params: dados, headers: admin.create_new_auth_token, as: :json

      # Assert
      expect(response).to have_http_status(:created)
      agente = Autonomia::Agents::Agent.find_by(account: account, agent_type: 'insurance_quote')
      expect(agente.name).to eq('Mia')
      expect(agente.specialists.count).to eq(1)
      expect(agente.instruction).to include('Corretora Exemplo')
    end

    # Clicar duas vezes não é erro do usuário: a tela mostra o que existe, em vez de uma mensagem
    # sobre algo que ela mesma pediu.
    it 'devolve o que existe quando ja ha um agente' do
      post base, params: dados, headers: admin.create_new_auth_token, as: :json
      primeiro = Autonomia::Agents::Agent.last

      post base, params: dados, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['payload']['id']).to eq(primeiro.id)
      expect(Autonomia::Agents::Agent.count).to eq(1)
    end

    it 'recusa nome vazio dizendo qual campo' do
      post base, params: { quote_agent: dados[:quote_agent].merge(name: '  ') },
                 headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('nome_invalido')
      expect(response.parsed_body['detail']).to include('agente')
    end

    it 'recusa comportamento que nao existe' do
      post base, params: { quote_agent: dados[:quote_agent].merge(behavior: 'agressivo') },
                 headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('comportamento_invalido')
    end

    # Uma conta não enxerga nem cria na outra.
    it 'nao cria na conta de outro' do
      outra = create(:account)
      Autonomia::Insurance::Config.enable_for!(outra)

      post "/api/v1/accounts/#{outra.id}/autonomia/insurance/quote_agent",
           params: dados, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found).or have_http_status(:unauthorized)
      expect(Autonomia::Agents::Agent.where(account: outra)).to be_empty
    end
  end
end

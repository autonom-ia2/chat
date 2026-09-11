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

    # O `detail` É O NOME DO CAMPO, NUNCA O VALOR (rodada 7 de #380, P2 do Codex): até 8b9800791f a porta
    # devolvia `detail: '$nomeAgente'` — o que o cliente mandou, de volta para ele. A tela traduz pelo
    # código (`comportamento_invalido`) e não mostra o `detail`; ele serve ao log.
    it 'recusa comportamento que nao existe dizendo o campo, sem ecoar o valor' do
      post base, params: { quote_agent: dados[:quote_agent].merge(behavior: '$nomeAgente') },
                 headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('comportamento_invalido')
      expect(response.parsed_body['detail']).to eq('comportamento')
      expect(response.body).not_to include('$nomeAgente')
      expect(Autonomia::Agents::Agent.count).to eq(0)
    end

    # MARCADOR RESERVADO DENTRO DE UMA ESCOLHA (rodada 6 de #380): a porta responde 422 com o campo e
    # nunca ecoa o valor. Sem a recusa na criação, o horário com `$nomeAgente` levantaria
    # `EscolhasIncompletas` dentro da transação — e este controller não herda o `rescue_from` da área de
    # agentes: 500 sem o nome do campo.
    it 'recusa nome com marcador reservado dizendo qual campo, sem ecoar o valor' do
      post base, params: { quote_agent: dados[:quote_agent].merge(broker_name: '$horarioAtendimento') },
                 headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('nome_invalido')
      expect(response.parsed_body['detail']).to include('corretora')
      expect(response.body).not_to include('$horarioAtendimento')
      expect(Autonomia::Agents::Agent.count).to eq(0)
    end

    it 'recusa horario com marcador reservado, sem ecoar o valor' do
      post base, params: { quote_agent: dados[:quote_agent].merge(business_hours: 'das 09h às 18h, $nomeAgente') },
                 headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('horario_invalido')
      expect(response.body).not_to include('$nomeAgente')
      expect(Autonomia::Agents::Agent.count).to eq(0)
    end

    # SLUG FORA DO CATÁLOGO NÃO É ERRO DE QUEM CLICOU. A constante de ferramentas apontar para um
    # slug inexistente é bug nosso — quem preencheu o formulário não tem como consertar. Devolver
    # 422 com a mensagem crua culparia o usuário e entregaria o catálogo interno de ferramentas.
    it 'nao devolve o catalogo interno quando a constante aponta para slug inexistente' do
      stub_const('Autonomia::Insurance::QuoteAgent::Builder::TODAS_AS_TOOLS',
                 %w[cotar_seguro slug_que_nao_existe])

      post base, params: dados, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:internal_server_error)
      expect(response.parsed_body['error']).to eq('configuracao_invalida')
      expect(response.body).not_to include('slug_que_nao_existe')
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

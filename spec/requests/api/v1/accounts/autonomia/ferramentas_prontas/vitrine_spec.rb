require 'rails_helper'

# #2858 F2 — a vitrine de ferramentas prontas. Quem inclui, liga, desliga, tira e experimenta: o administrador e quem
# tem a chave "Ferramentas dos agentes" (`autonomia_tools_manage`), com a flag da vitrine na conta. O "Incluir" passa a
# pessoa real ao serviço (condição da Funções). A Lia fica de fora. Uma conta nunca vê nem mexe nas prontas de outra.
RSpec.describe 'Vitrine de ferramentas prontas', type: :request do
  include FerramentasProntasHelper

  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:agent) { Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'custom') }
  let(:lia) { Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'insurance_quote') }
  let(:base) { "/api/v1/accounts/#{account.id}/autonomia/ferramentas_prontas" }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:flag_vitrine) { Autonomia::FerramentasProntas::FLAG_VITRINE }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  before do
    resolver_hosts_das_prontas
    ligar_consultas(account)
    account.enable_features!(flag_vitrine)
  end

  def com_funcao(permissoes, conta: account)
    pessoa = create(:user, account: conta, role: :agent)
    pessoa.account_users.find_by(account: conta).update!(custom_role: create(:custom_role, account: conta, permissions: permissoes))
    pessoa
  end

  def incluir(pessoa, fonte: 'cep', agente: agent, usar_quando: 'o cliente informar o CEP')
    post "#{base}/incluir", params: { fonte: fonte, agent_id: agente.id, usar_quando: usar_quando },
                            headers: pessoa.create_new_auth_token, as: :json
  end

  describe 'quem pode' do
    it 'recusa quem não é administrador nem tem a chave das ferramentas, em toda ação' do
      pessoa = com_funcao(%w[autonomia_view autonomia_manage])

      get base, headers: pessoa.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
      incluir(pessoa)
      expect(response).to have_http_status(:unauthorized)
      post "#{base}/experimentar", params: { fonte: 'cep', valor: '01001000' }, headers: pessoa.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(agent.tools.count).to eq(0)
    end

    it 'deixa quem tem só a chave das ferramentas incluir, e grava quem incluiu' do
      pessoa = com_funcao(%w[autonomia_tools_manage])

      incluir(pessoa)

      expect(response).to have_http_status(:created)
      ferramenta = agent.tools.sole
      expect(ferramenta).to have_attributes(fonte_pronta: 'cep', enabled: true, description: 'o cliente informar o CEP')
      expect(Autonomia::FerramentasProntas::Acesso.sole.incluida_por_id).to eq(pessoa.id)
    end

    it 'passa a pessoa real ao Incluir' do
      expect(Autonomia::FerramentasProntas::Incluir).to receive(:new)
        .with(hash_including(user: admin, account: account, agent: agent, fonte: 'cep')).and_call_original

      incluir(admin)
      expect(response).to have_http_status(:created)
    end

    it 'sem a flag da vitrine, nada responde' do
      account.disable_features!(flag_vitrine)

      get base, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      incluir(admin)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET index' do
    it 'lista só as fontes liberadas para a conta e as prontas incluídas, sem nada técnico' do
      incluir(admin, fonte: 'cpf')
      account.disable_features!(Autonomia::FerramentasProntas::FLAG_CONSULTAS)

      get base, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      corpo = response.parsed_body
      expect(corpo['fontes'].pluck('chave')).to contain_exactly('cep', 'cnpj', 'fipe')
      esperado = { 'agente_id' => agent.id, 'fonte' => 'cpf', 'ligada' => true, 'usar_quando' => 'o cliente informar o CEP' }
      expect(corpo['incluidas'].sole).to include(esperado)
      expect(response.body).not_to include('brasilapi', 'http', 'chave_interna')
    end

    it 'não mostra as prontas de outra conta' do
      outra = create(:account)
      ligar_consultas(outra)
      agente_de_fora = Autonomia::Agents::Agent.create!(account: outra, name: 'Outro', agent_type: 'custom')
      incluir_pronta('cep', conta: outra, agente: agente_de_fora)

      get base, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['incluidas']).to eq([])
    end
  end

  describe 'POST incluir' do
    it 'recusa a Lia, com o motivo' do
      incluir(admin, agente: lia)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['motivo']).to eq('agente_de_cotacao')
      expect(lia.tools.count).to eq(0)
    end

    it 'não acha o agente de outra conta' do
      outra = create(:account)
      agente_de_fora = Autonomia::Agents::Agent.create!(account: outra, name: 'Outro', agent_type: 'custom')

      incluir(admin, agente: agente_de_fora)

      expect(response).to have_http_status(:not_found)
      expect(agente_de_fora.tools.count).to eq(0)
    end

    it 'recusa a fonte fora do catálogo' do
      incluir(admin, fonte: 'nao_existe')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['motivo']).to eq('fonte_desconhecida')
    end
  end

  describe 'PATCH e DELETE da pronta' do
    let!(:ferramenta) { incluir_pronta('cep', conta: account, agente: agent) }

    it 'desliga, religa e tira' do
      patch "#{base}/#{ferramenta.id}", params: { ligada: false }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(ferramenta.reload.enabled).to be(false)

      patch "#{base}/#{ferramenta.id}", params: { ligada: true }, headers: admin.create_new_auth_token, as: :json
      expect(ferramenta.reload.enabled).to be(true)

      delete "#{base}/#{ferramenta.id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:no_content)
      expect(Autonomia::Agents::Tool.exists?(ferramenta.id)).to be(false)
    end

    it 'não mexe na ferramenta feita à mão nem na pronta de outra conta' do
      manual = Autonomia::Agents::Tool.create!(account: account, agent: agent, name: 'Frete', endpoint_url: 'https://api.loja.test/frete')
      outra = create(:account)
      ligar_consultas(outra)
      de_fora = incluir_pronta('cep', conta: outra, agente: Autonomia::Agents::Agent.create!(account: outra, name: 'X', agent_type: 'custom'))

      [manual, de_fora].each do |alvo|
        delete "#{base}/#{alvo.id}", headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:not_found)
        expect(Autonomia::Agents::Tool.exists?(alvo.id)).to be(true)
      end
    end
  end

  describe 'POST experimentar' do
    it 'consulta a fonte e devolve os dados, contando no limite do dia da conta' do
      fonte_responde('https://brasilapi.com.br/api/cep/v2/01001000',
                     { cep: '01001000', state: 'SP', city: 'São Paulo', neighborhood: 'Sé', street: 'Praça da Sé' })

      post "#{base}/experimentar", params: { fonte: 'cep', valor: '01001-000' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['situacao']).to eq('encontrado')
      expect(response.parsed_body['dados']).to include('logradouro' => 'Praça da Sé', 'cidade' => 'São Paulo')
      expect(Autonomia::FerramentasProntas::Uso.sole.consultas).to eq(1)
    end

    it 'com a fonte fora, diz que não conseguiu' do
      fonte_fora('https://brasilapi.com.br/api/cep/v2/01001000')
      fonte_fora('https://viacep.com.br/ws/01001000/json/')

      post "#{base}/experimentar", params: { fonte: 'cep', valor: '01001000' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('situacao' => 'nao_consegui_consultar')
    end

    it 'o valor que não serve não sai para a rede' do
      post "#{base}/experimentar", params: { fonte: 'cep', valor: 'abc' }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body).to eq('situacao' => 'pedido_invalido')
      expect(a_request(:get, ->(uri) { uri.host == 'brasilapi.com.br' })).not_to have_been_made
    end

    it 'o Banco Central não pede valor: dá o dólar' do
      do_bcb = ->(uri) { uri.host == 'olinda.bcb.gov.br' }
      boletins = [{ cotacaoCompra: 5.514, cotacaoVenda: 5.5146, dataHoraCotacao: '2026-11-09 13:06:31' }]
      stub_request(:get, do_bcb).to_return(status: 200, body: { value: boletins }.to_json,
                                           headers: { 'Content-Type' => 'application/json;charset=UTF-8' })

      post "#{base}/experimentar", params: { fonte: 'banco_central' }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['dados']).to include('compra' => 5.514, 'venda' => 5.5146)
      expect(response.parsed_body['situacao']).to eq('encontrado')
    end
  end

  describe 'POST buscas_sem_resultado' do
    it 'conta a busca sem resultado da conta, cortada e sem acento de fora' do
      2.times do
        post "#{base}/buscas_sem_resultado", params: { termo: '  Passagem de Avião  ' }, headers: admin.create_new_auth_token, as: :json
      end

      expect(response).to have_http_status(:no_content)
      expect(Autonomia::FerramentasProntas::BuscasSemResultado.da_conta(account)).to eq([['passagem de avião', 2]])
    end
  end
end

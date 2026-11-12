require 'rails_helper'

# #2858 F7 — os cards Premium na API da vitrine: aparecem só com a flag do Premium, cada um com as 20 grátis, quantas
# restam à conta e os preços depois delas; o "Experimente" consulta pelas grátis do card e, acabadas elas, só com o clique
# no preço; o "Incluir" recusa sem a flag. Nada técnico na resposta (nem dataset, nem rota, nem custo).
RSpec.describe 'Vitrine de ferramentas prontas: Premium', type: :request do
  include FerramentasProntasHelper

  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:outra_conta) { create(:account) }
  let(:agent) { Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'custom') }
  let(:base) { "/api/v1/accounts/#{account.id}/autonomia/ferramentas_prontas" }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:premium) { %w[certidoes_empresa raio_x_empresa conferir_pessoa historico_placa risco_endereco imovel_rural contato_empresa] }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  before do
    ligar_premium(account)
    account.enable_features!(Autonomia::FerramentasProntas::FLAG_VITRINE)
  end

  def fontes
    get base, headers: admin.create_new_auth_token, as: :json
    response.parsed_body['fontes'].index_by { |fonte| fonte['chave'] }
  end

  it 'mostra os 7 cards com as grátis que restam no mês e os preços; um card não mexe no do outro, nem outra conta' do
    saldo_premium!(account, 'certidoes_empresa', 5)
    saldo_premium!(outra_conta, 'raio_x_empresa', 20)
    # O mês passado não conta: as 20 grátis renovam todo mês.
    saldo_premium!(account, 'raio_x_empresa', 20, mes: Autonomia::FerramentasProntas::Premium.mes_da_conta(account).prev_month)

    lista = fontes

    expect(lista.keys).to include(*premium)
    expect(lista['certidoes_empresa']['premium']).to eq('gratis' => 20, 'restantes' => 15, 'precos' => %w[0.06 0.15],
                                                        'confere_documento' => true)
    expect(lista['raio_x_empresa']['premium']).to eq('gratis' => 20, 'restantes' => 20, 'precos' => %w[0.09 0.12],
                                                     'confere_documento' => true)
    expect(lista['historico_placa']['premium']).to eq('gratis' => 20, 'restantes' => 20, 'precos' => %w[0.09],
                                                      'confere_documento' => false)
    expect(lista['imovel_rural']['premium']['precos']).to eq(%w[0.15 0.23])
    expect(lista['cep']).not_to have_key('premium')
    expect(response.body).not_to include('ondemand', 'bigdatacorp', 'custo')
  end

  # A regra "CPF ou CNPJ com número errado não conta" do "Quanto custa" só vale no card que recebe CPF ou CNPJ: é o
  # dígito verificador desses parâmetros que recusa o pedido antes da BigDataCorp. Placa e endereço não têm documento.
  it 'diz em cada card se ele confere CPF ou CNPJ (a regra do número errado só vale nele)' do
    lista = fontes

    confere = premium.index_with { |chave| lista[chave]['premium']['confere_documento'] }
    expect(confere).to eq('certidoes_empresa' => true, 'raio_x_empresa' => true, 'conferir_pessoa' => true,
                          'historico_placa' => false, 'risco_endereco' => false, 'imovel_rural' => true,
                          'contato_empresa' => true)
  end

  it 'passadas as 20, restam 0 (nunca negativo)' do
    saldo_premium!(account, 'historico_placa', 27)

    expect(fontes['historico_placa']['premium']['restantes']).to eq(0)
  end

  it 'sem a flag do Premium, os cards somem e o "Incluir" recusa; as grátis seguem' do
    account.disable_features!(Autonomia::FerramentasProntas::Premium::FLAG)

    expect(fontes.keys).not_to include(*premium)
    expect(fontes.keys).to include('cep')
    post "#{base}/incluir", params: { fonte: 'certidoes_empresa', agent_id: agent.id, usar_quando: 'pedirem certidão' },
                            headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['motivo']).to eq('desligada')
  end

  it 'o "Incluir" de um card Premium funciona com a flag' do
    post "#{base}/incluir", params: { fonte: 'certidoes_empresa', agent_id: agent.id, usar_quando: 'pedirem certidão' },
                            headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:created)
  end

  # Decisão A do Rodrigo (11/11): o Premium ganha o "Experimente", que usa as grátis do card. O modelo da conta é
  # dublado e a BigDataCorp vem do WebMock: nenhuma chamada real.
  describe 'o "Experimente" do card Premium' do
    let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }
    let(:chamada) do
      { 'name' => 'pronta_certidoes_empresa', 'call_id' => 'c1',
        'arguments' => { consulta: 'divida_uniao', cnpj: FerramentasPremiumHelper::CNPJ_EXEMPLO }.to_json }
    end

    around { |example| com_credencial_da_bigdatacorp { example.run } }

    before do
      cache_em_memoria
      token_da_bigdatacorp
      bigdatacorp_responde('/ondemand', 'ondemand_pgfn_company', 'OnlineCertificates', [{ 'Origin' => 'PGFN', 'BaseStatus' => 'NEGATIVA' }])
      allow(Crm::Ai::CredentialResolver).to receive(:new)
        .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'chave-de-teste', source: :system }))
      allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
      allow(cliente).to receive(:create_with_tool_executor) do |**_kwargs, &executor|
        executor.call([chamada])
        { text: { mais_provavel: false }.to_json }
      end
    end

    def experimentar(**extras)
      post "#{base}/experimentar", params: { fonte: 'certidoes_empresa', valor: 'dívida com a União da 11.222.333/0001-81', **extras },
                                   headers: admin.create_new_auth_token, as: :json
      response.parsed_body
    end

    def acompanhar(pedido, quem: admin, conta: account)
      get "/api/v1/accounts/#{conta.id}/autonomia/ferramentas_prontas/experimentar/#{pedido}", headers: quem.create_new_auth_token, as: :json
      response.body.present? ? response.parsed_body : nil
    end

    # Revisor (ALTO 1, 12/11): a consulta paga não cabe no corte de 15 s do pedido web. O POST responde 202 com o id do
    # pedido; a consulta roda em segundo plano (`ExperimentePagoJob`); a tela pergunta pelo id até o resultado.
    it 'o caminho completo: 202 com o pedido, "consultando" e depois o resultado com o contador novo', :aggregate_failures do
      corpo = experimentar

      expect(response).to have_http_status(:accepted)
      expect(corpo).to include('situacao' => 'consultando', 'pedido' => be_present)
      expect(corpo['premium']).to include('restantes' => 20)
      expect(Autonomia::FerramentasProntas::ExperimentePagoJob).to have_been_enqueued.with(corpo['pedido'])
      expect(acompanhar(corpo['pedido'])).to eq('situacao' => 'consultando')
      expect(chamou_a_bigdatacorp?).to be(false)

      perform_enqueued_jobs(only: Autonomia::FerramentasProntas::ExperimentePagoJob)
      resultado = acompanhar(corpo['pedido'])

      expect(response).to have_http_status(:ok)
      expect(resultado['situacao']).to eq('encontrado')
      expect(resultado['premium']).to include('gratis' => 20, 'restantes' => 19)
      expect(resultado.keys).not_to include('valor', 'conta', 'confirmou_preco')
      expect(registros_premium.sole).to have_attributes(resultado: 'encontrado', cobranca: 'gratis', autonomia_agent_id: nil)
      expect(response.body).not_to include('bigdatacorp', 'custo', 'ondemand', '11.222.333')
    end

    it 'o pedido é preso à conta: o id de outra conta, ou um id que não existe, dá 404' do
      pedido = experimentar['pedido']
      outra_conta.enable_features!(Autonomia::FerramentasProntas::FLAG_VITRINE)
      ligar_premium(outra_conta)
      outro_admin = create(:user, :administrator, account: outra_conta)

      acompanhar(pedido, quem: outro_admin, conta: outra_conta)
      expect(response).to have_http_status(:not_found)
      acompanhar(SecureRandom.uuid)
      expect(response).to have_http_status(:not_found)
    end

    it 'o acompanhamento tem a mesma porta do POST: sem a chave das ferramentas, 401; sem a vitrine, 404' do
      pedido = experimentar['pedido']
      agente_comum = create(:user, account: account, role: :agent)

      acompanhar(pedido, quem: agente_comum)
      expect(response).to have_http_status(:unauthorized)
      account.disable_features!(Autonomia::FerramentasProntas::FLAG_VITRINE)
      acompanhar(pedido)
      expect(response).to have_http_status(:not_found)
    end

    it 'acabadas as grátis, só consulta com o clique no preço' do
      saldo_premium!(account, 'certidoes_empresa', 20)

      expect(experimentar).to include('situacao' => 'confirmar_preco')
      expect(response).to have_http_status(:ok)
      expect(Autonomia::FerramentasProntas::ExperimentePagoJob).not_to have_been_enqueued

      pedido = experimentar(confirmou_preco: true)['pedido']
      perform_enqueued_jobs(only: Autonomia::FerramentasProntas::ExperimentePagoJob)

      expect(acompanhar(pedido)['situacao']).to eq('encontrado')
      expect(registros_premium.sole).to have_attributes(cobranca: 'cobrada', numero: 21)
    end

    it 'confirmou_preco só vale como verdadeiro: outro valor não paga' do
      saldo_premium!(account, 'certidoes_empresa', 20)

      expect(experimentar(confirmou_preco: 'sim')).to include('situacao' => 'confirmar_preco')
      expect(experimentar(confirmou_preco: ['true'])).to include('situacao' => 'confirmar_preco')
      expect(chamou_a_bigdatacorp?).to be(false)
    end
  end
end

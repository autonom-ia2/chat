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

  after { Redis::Alfred.delete(Autonomia::FerramentasProntas::BuscasSemResultado.chave(account)) }

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

    it 'recusa também ligar, tirar e registrar busca sem a chave' do
      pessoa = com_funcao(%w[autonomia_view autonomia_manage])
      pronta = incluir_pronta('cep', conta: account, agente: agent)

      patch "#{base}/#{pronta.id}", params: { ligada: false }, headers: pessoa.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
      delete "#{base}/#{pronta.id}", headers: pessoa.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
      post "#{base}/buscas_sem_resultado", params: { termo: 'avião' }, headers: pessoa.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(pronta.reload.enabled).to be(true)
    end

    it 'deixa quem tem só a chave das ferramentas incluir, e grava quem incluiu' do
      pessoa = com_funcao(%w[autonomia_tools_manage])

      incluir(pessoa)

      expect(response).to have_http_status(:created)
      ferramenta = agent.tools.sole
      expect(ferramenta).to have_attributes(fonte_pronta: 'cep', enabled: true, description: 'o cliente informar o CEP')
      expect(Autonomia::FerramentasProntas::Acesso.sole.incluida_por_id).to eq(pessoa.id)
    end

    it 'grava quem incluiu mesmo quando o acesso nasceu no Experimente' do
      pessoa = com_funcao(%w[autonomia_tools_manage])
      fonte_responde('https://viacep.com.br/ws/01001000/json/', { cep: '01001-000', localidade: 'São Paulo', uf: 'SP' })
      post "#{base}/experimentar", params: { fonte: 'cep', valor: '01001000' }, headers: pessoa.create_new_auth_token, as: :json
      expect(Autonomia::FerramentasProntas::Acesso.sole.incluida_por_id).to be_nil

      incluir(pessoa)

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
      expect(response.parsed_body).to eq('motivo' => 'desligada')
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

    it 'F5: a base baixada leva o dia em que foi atualizada (nil antes de baixar); as outras fontes não levam o campo' do
      account.enable_features!(Autonomia::FerramentasProntas::Bases::FLAG)
      estado = Autonomia::FerramentasProntas::Bases::Estado
      estado.create!(base: 'aeronaves', geracao_ativa: 1, atualizado_em: Time.zone.parse('2026-11-11 10:47'), falhou_em: 1.hour.ago)
      estado.create!(base: 'geracao_solar', falhou_em: 1.hour.ago, motivo_da_falha: 'erro_da_fonte')

      get base, headers: admin.create_new_auth_token, as: :json

      fontes = response.parsed_body['fontes'].index_by { |fonte| fonte['chave'] }
      expect(fontes['aeronaves']).to eq('chave' => 'aeronaves', 'atualizado_em' => '2026-11-11', 'em_preparacao' => false)
      expect(fontes['transportadoras']).to eq('chave' => 'transportadoras', 'atualizado_em' => nil, 'em_preparacao' => false)
      expect(fontes['geracao_solar']).to eq('chave' => 'geracao_solar', 'atualizado_em' => nil, 'em_preparacao' => true)
      expect(fontes['cep']).to eq('chave' => 'cep')
      expect(response.body).not_to include('erro_da_fonte')
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

  # Decisão do Rodrigo (11/11): a fonte continua no catálogo, para os agentes de garantia e de transporte (#2881), mas
  # sai da vitrine como card avulso.
  describe 'fonte fora da vitrine (Produtos das seguradoras)' do
    before { account.enable_features!('agente_ferramentas_prontas_lote2') }

    it 'não aparece na lista; a que o agente já tem continua listada, e ele ainda consulta' do
      ja_tem = pronta_ja_incluida('produtos_seguradoras', conta: account, agente: agent)

      get base, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['fontes'].pluck('chave')).to include('corretor_susep')
      expect(response.parsed_body['fontes'].pluck('chave')).not_to include('produtos_seguradoras')
      expect(response.parsed_body['incluidas'].sole).to include('id' => ja_tem.id, 'fonte' => 'produtos_seguradoras', 'ligada' => true)
      expect(Autonomia::FerramentasProntas.no_turno?(ja_tem, agent)).to be(true)
    end

    it 'o Incluir e o Experimente recusam, sem consultar nada' do
      incluir(admin, fonte: 'produtos_seguradoras')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['motivo']).to eq('fora_da_vitrine')
      expect(agent.tools.count).to eq(0)

      post "#{base}/experimentar", params: { fonte: 'produtos_seguradoras', valor: 'Allianz transporte' },
                                   headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body).to eq('situacao' => 'desligada')
      expect(a_request(:get, /opinbrasil/)).not_to have_been_made
    end

    it 'a que o agente já tem ainda se desliga e se tira' do
      ja_tem = pronta_ja_incluida('produtos_seguradoras', conta: account, agente: agent)

      patch "#{base}/#{ja_tem.id}", params: { ligada: false }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(ja_tem.reload.enabled).to be(false)

      delete "#{base}/#{ja_tem.id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:no_content)
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

    it 'aceita verdadeiro e falso também como texto, que é como o Guia manda' do
      patch "#{base}/#{ferramenta.id}", params: { ligada: 'false' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(ferramenta.reload.enabled).to be(false)
    end

    it 'recusa ligada que não é verdadeiro nem falso' do
      ['abc', [true], { x: 1 }, nil].each do |valor|
        patch "#{base}/#{ferramenta.id}", params: { ligada: valor }, headers: admin.create_new_auth_token, as: :json
        expect(response.status).to be_in([400, 422])
      end
      expect(ferramenta.reload.enabled).to be(true)
    end

    # #2881 — a frase "Use quando" de uma pronta já incluída.
    it 'altera a frase "Use quando" sem mexer no liga/desliga, e o agente passa a ler a frase nova' do
      ferramenta.update!(enabled: false)

      patch "#{base}/#{ferramenta.id}", params: { usar_quando: '  Use quando o cliente informar   o CEP da obra. ' },
                                        headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      frase = 'Use quando o cliente informar o CEP da obra.'
      expect(response.parsed_body).to include('id' => ferramenta.id, 'ligada' => false, 'usar_quando' => frase)
      expect(ferramenta.reload).to have_attributes(enabled: false, description: frase)
      expect(ferramenta.openai_schema[:description]).to include("Use quando: #{frase}")
    end

    it 'muda a frase e o liga/desliga no mesmo pedido' do
      patch "#{base}/#{ferramenta.id}", params: { ligada: false, usar_quando: 'Use quando pedirem o endereço.' },
                                        headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(ferramenta.reload).to have_attributes(enabled: false, description: 'Use quando pedirem o endereço.')
    end

    it 'corta a frase no limite do Incluir e, vazia, volta à frase padrão da ferramenta' do
      patch "#{base}/#{ferramenta.id}", params: { usar_quando: 'a' * 600 }, headers: admin.create_new_auth_token, as: :json
      expect(ferramenta.reload.description.length).to eq(Autonomia::FerramentasProntas::Incluir::MAX_USAR_QUANDO)

      ['   ', nil].each do |vazia|
        ferramenta.update!(description: 'Use quando pedirem o endereço.')
        patch "#{base}/#{ferramenta.id}", params: { usar_quando: vazia }, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['usar_quando']).to be_nil
        expect(ferramenta.reload.description).to be_nil
      end
    end

    it 'recusa frase que não é texto, e ligada inválida mesmo com a frase certa' do
      ferramenta.update!(description: 'Use quando pedirem o endereço.')

      [['abc'], { x: 1 }].each do |valor|
        patch "#{base}/#{ferramenta.id}", params: { usar_quando: valor }, headers: admin.create_new_auth_token, as: :json
        expect(response.status).to be_in([400, 422])
      end
      patch "#{base}/#{ferramenta.id}", params: { ligada: 'abc', usar_quando: 'Outra frase.' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('motivo' => 'ligada_invalida')

      expect(ferramenta.reload).to have_attributes(enabled: true, description: 'Use quando pedirem o endereço.')
    end

    it 'sem a chave das ferramentas, a frase não muda' do
      pessoa = com_funcao(%w[autonomia_view autonomia_manage])

      patch "#{base}/#{ferramenta.id}", params: { usar_quando: 'Outra frase.' }, headers: pessoa.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(ferramenta.reload.description).not_to eq('Outra frase.')
    end

    it 'não mexe na pronta da Lia' do
      da_lia = Autonomia::Agents::Tool.create!(account: account, agent: lia, name: 'CEP', slug: 'pronta_cep', fonte_pronta: 'cep',
                                               http_method: 'GET', endpoint_url: '', timeout_seconds: 5)

      delete "#{base}/#{da_lia.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(Autonomia::Agents::Tool.exists?(da_lia.id)).to be(true)
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
      fonte_responde('https://viacep.com.br/ws/01001000/json/',
                     { cep: '01001-000', localidade: 'São Paulo', uf: 'SP', bairro: 'Sé', logradouro: 'Praça da Sé' })

      post "#{base}/experimentar", params: { fonte: 'cep', valor: '01001-000' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['situacao']).to eq('encontrado')
      expect(response.parsed_body['dados']).to include('logradouro' => 'Praça da Sé', 'cidade' => 'São Paulo')
      expect(Autonomia::FerramentasProntas::Uso.sole.consultas).to eq(1)
    end

    it 'conta no limite do dia: passou dele, não sai para a rede' do
      cep = 'https://viacep.com.br/ws/01001000/json/'
      fonte_responde(cep, { cep: '01001-000', localidade: 'São Paulo', uf: 'SP' })
      Autonomia::FerramentasProntas::Acesso.create!(account: account, fonte: 'cep', limite_diario: 1)

      2.times { post "#{base}/experimentar", params: { fonte: 'cep', valor: '01001000' }, headers: admin.create_new_auth_token, as: :json }

      expect(response.parsed_body).to eq('situacao' => 'nao_consegui_consultar')
      expect(a_request(:get, cep)).to have_been_made.once
      expect(Autonomia::FerramentasProntas::Uso.sole).to have_attributes(consultas: 1, recusadas: 1)
    end

    it 'o valor digitado não vai para o log' do
      filtro = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

      expect(filtro.filter('fonte' => 'cpf', 'valor' => '11144477735')).to eq('fonte' => 'cpf', 'valor' => '[FILTERED]')
    end

    it 'com a fonte fora, diz que não conseguiu' do
      fonte_fora('https://viacep.com.br/ws/01001000/json/')
      fonte_fora('https://cep.awesomeapi.com.br/json/01001000')
      fonte_fora('https://brasilapi.com.br/api/cep/v2/01001000')

      post "#{base}/experimentar", params: { fonte: 'cep', valor: '01001000' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('situacao' => 'nao_consegui_consultar')
    end

    it 'o valor que não serve não sai para a rede' do
      post "#{base}/experimentar", params: { fonte: 'cep', valor: 'abc' }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body).to eq('situacao' => 'pedido_invalido')
      expect(a_request(:get, ->(uri) { uri.host == 'brasilapi.com.br' })).not_to have_been_made
    end

    it 'Bancos: o exemplo é o nome ("Itaú"), e o código digitado continua valendo' do
      account.enable_features!(Autonomia::FerramentasProntas::FLAG_CONSULTAS)
      itau = { ispb: '60701190', name: 'ITAÚ UNIBANCO S.A.', code: 341, fullName: 'ITAÚ UNIBANCO S.A.' }
      fonte_responde('https://brasilapi.com.br/api/banks/v1', [itau])
      fonte_responde('https://brasilapi.com.br/api/banks/v1/341', { ispb: '60701190', name: 'ITAÚ UNIBANCO S.A.', code: 341 })

      post "#{base}/experimentar", params: { fonte: 'bancos', valor: 'Itaú' }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['dados']['bancos']).to eq([{ 'codigo' => '341', 'nome' => 'ITAÚ UNIBANCO S.A.',
                                                               'nome_completo' => 'ITAÚ UNIBANCO S.A.', 'ispb' => '60701190' }])

      post "#{base}/experimentar", params: { fonte: 'bancos', valor: '341' }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['dados']).to include('codigo' => '341', 'nome' => 'ITAÚ UNIBANCO S.A.')
    end

    it 'DDD: o telefone inteiro serve no Experimente' do
      account.enable_features!(Autonomia::FerramentasProntas::FLAG_CONSULTAS)
      fonte_responde('https://brasilapi.com.br/api/ddd/v1/34', { state: 'MG', cities: %w[UBERLANDIA] })

      post "#{base}/experimentar", params: { fonte: 'ddd', valor: '34 99999-0000' }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['dados']).to include('ddd' => '34', 'uf' => 'MG')
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

    # "Onix 2020": a IA da conta (dublada) escolhe a consulta; a tela recebe só a saída da fonte, nunca o texto dela.
    it 'a FIPE aceita "carro e ano" em texto livre, pela IA da conta' do
      fonte_responde('https://brasilapi.com.br/api/fipe/preco/v1/004517-9',
                     [{ valor: 'R$ 60.822,00', marca: 'GM - Chevrolet', modelo: 'Onix LT 1.0', anoModelo: 2020, combustivel: 'Flex',
                        codigoFipe: '004517-9', mesReferencia: 'novembro de 2026', tipoVeiculo: 1 }])
      cliente = instance_double(Crm::Ai::ResponsesClient)
      allow(Crm::Ai::CredentialResolver).to receive(:new)
        .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'chave-de-teste', source: :system }))
      allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
      allow(cliente).to receive(:create_with_tool_executor) do |**_kwargs, &executor|
        executor.call([{ 'name' => 'pronta_fipe', 'call_id' => 'c1',
                         'arguments' => { consulta: 'preco', tipo: 'carros', codigo_fipe: '004517-9' }.to_json }])
        { text: '{"mais_provavel":false}' }
      end

      post "#{base}/experimentar", params: { fonte: 'fipe', valor: 'Onix 2020' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.keys).to contain_exactly('situacao', 'dados')
      expect(response.parsed_body['situacao']).to eq('encontrado')
      expect(response.parsed_body.to_json).to include('60822.0')
      expect(Autonomia::FerramentasProntas::Uso.find_by(account_id: account.id, fonte: 'fipe').consultas).to eq(1)
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

    it 'não guarda termo com cara de documento, telefone ou e-mail' do
      post "#{base}/buscas_sem_resultado", params: { termo: '111.444.777-35' }, headers: admin.create_new_auth_token, as: :json
      post "#{base}/buscas_sem_resultado", params: { termo: 'ana@exemplo.test' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:no_content)
      expect(Autonomia::FerramentasProntas::BuscasSemResultado.da_conta(account)).to eq([])
    end

    it 'sem Redis, a busca segue sem erro' do
      allow(Redis::Alfred).to receive(:with).and_raise(Redis::CannotConnectError)

      post "#{base}/buscas_sem_resultado", params: { termo: 'avião' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:no_content)
    end
  end
end

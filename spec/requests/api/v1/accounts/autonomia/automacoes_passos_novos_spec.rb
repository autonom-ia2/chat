require 'rails_helper'

# #2932–#2934: o que a tela dos passos novos pergunta ao servidor (contar a lista, testar a busca) e a marca de bloco.
RSpec.describe 'Api::V1::Accounts::Autonomia::AutomacoesPassosNovos', :automacao_motor, type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/autonomia/automacoes" }
  let(:url) { 'https://loja.exemplo.com/pedidos/1?token=abc' }

  around { |exemplo| with_modified_env(FRONTEND_URL: 'https://app.plataforma.com') { exemplo.run } }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_editor', 'automacao_passos_novos')
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('loja.exemplo.com').and_return(['93.184.216.34'])
    allow(Resolv).to receive(:getaddresses).with('interno.exemplo.com').and_return(['10.0.0.5'])
    allow(Resolv).to receive(:getaddresses).with('app.plataforma.com').and_return(['151.101.1.69'])
  end

  def com_funcao(*permissoes)
    create(:user, account: account, role: :agent).tap do |pessoa|
      pessoa.account_users.find_by(account: account).update!(custom_role: create(:custom_role, account: account, permissions: permissoes))
    end
  end

  def postar(acao, corpo, quem = admin) = post("#{base}/#{acao}", params: corpo, headers: quem.create_new_auth_token, as: :json)

  describe 'POST contar_lista' do
    before do
      account.labels.create!(title: 'vip')
      %w[Ana Bruno].each { |nome| account.contacts.create!(name: nome).update!(label_list: ['vip']) }
    end

    it 'conta quem entraria hoje, até o teto, com os primeiros nomes', :aggregate_failures do
      postar('contar_lista', { lista: { de: 'etiqueta', etiqueta: 'vip' }, teto: 1 })

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('total' => 1, 'fora_do_teto' => 1, 'mais_alem' => false, 'teto' => 1)
      expect(response.parsed_body['primeiros'].size).to eq(1)
    end

    it 'a lista que não é da conta volta a frase', :aggregate_failures do
      postar('contar_lista', { lista: { de: 'etiqueta', etiqueta: 'outra' }, teto: 10 })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.automacao.receita.lista.etiqueta_de_fora', passo: ''))
    end

    it 'sem automation_manage recusa, e sem a flag não existe', :aggregate_failures do
      postar('contar_lista', { lista: { de: 'etiqueta', etiqueta: 'vip' }, teto: 1 }, com_funcao('automation_view'))
      expect(response).to have_http_status(:unauthorized)

      account.disable_features!('automacao_passos_novos')
      postar('contar_lista', { lista: { de: 'etiqueta', etiqueta: 'vip' }, teto: 1 })
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST testar_consulta' do
    it 'busca de verdade e volta cada dado com o valor e um nome do dia a dia', :aggregate_failures do
      stub_request(:get, url).to_return(status: 200, body: { pedido: { dataPrevista: '18/11' } }.to_json)

      postar('testar_consulta', { fonte: { de: 'endereco', url: url } })

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['dados']).to eq([{ 'caminho' => 'pedido.dataPrevista', 'valor' => '18/11', 'rotulo' => 'Pedido data prevista' }])
    end

    it 'recusa o endereço interno, também o nome que resolve para dentro, sem chamar nada', :aggregate_failures do
      postar('testar_consulta', { fonte: { de: 'endereco', url: 'https://127.0.0.1/x' } })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['motivo']).to eq('consulta_endereco_interno')

      postar('testar_consulta', { fonte: { de: 'endereco', url: 'https://interno.exemplo.com/x' } })
      expect(response.parsed_body).to include('ok' => false, 'motivo' => 'consulta_endereco_interno')
    end

    it 'pede a chave de integrações' do
      postar('testar_consulta', { fonte: { de: 'endereco', url: url } }, com_funcao('automation_manage'))

      expect(response).to have_http_status(:forbidden)
    end

    describe 'consulta pronta' do
      include FerramentasProntasHelper

      before do
        resolver_hosts_das_prontas
        ligar_prontas(account)
      end

      it 'busca com o exemplo, sem a chave de integrações, e volta cada dado com o rótulo pronto', :aggregate_failures do
        fonte_responde('https://viacep.com.br/ws/01310100/json/',
                       { cep: '01310-100', logradouro: 'Avenida Paulista', bairro: 'Bela Vista', localidade: 'São Paulo', uf: 'SP' })

        postar('testar_consulta', { fonte: { de: 'pronta', consulta: 'cep', exemplos: { cep: '01310-100' } } }, com_funcao('automation_manage'))

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['dados'].first).to eq('caminho' => 'logradouro', 'valor' => 'Avenida Paulista',
                                                          'rotulo' => I18n.t('autonomia.automacao.consultas_prontas.cep.dados.logradouro'))
      end

      it 'a consulta que não existe é recusada com a frase' do
        postar('testar_consulta', { fonte: { de: 'pronta', consulta: 'loja', exemplos: {} } })

        expect(response.parsed_body).to include('ok' => false, 'motivo' => 'consulta_pronta_desligada')
      end
    end
  end

  describe 'GET consultas_prontas' do
    it 'lista as consultas, com o que falta na que a conta não pode usar', :aggregate_failures do
      account.enable_features!(Autonomia::FerramentasProntas::FLAG)

      get "#{base}/consultas_prontas", headers: com_funcao('automation_manage').create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      consultas = response.parsed_body['consultas']
      expect(consultas.pluck('id')).to eq(%w[cep cnpj fipe cpf])
      expect(consultas.first).to include('disponivel' => true, 'falta' => nil)
      expect(consultas.last['disponivel']).to be(false)
      expect(consultas.last['falta']).to be_present
    end

    it 'pede a chave de montar automações' do
      get "#{base}/consultas_prontas", headers: com_funcao('automation_view').create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH a marca de bloco' do
    let(:bloco) do
      create(:autonomia_automacao, account: account).tap do |definicao|
        definicao.salvar_versao!(receita: { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [{ 'id' => 'b1', 'tipo' => 'parar' }] },
                                 autor: admin)
      end
    end

    def marcar(definicao, valor) = patch("#{base}/#{definicao.id}", params: { bloco: valor }, headers: admin.create_new_auth_token, as: :json)

    it 'marca e desliga; tirar a marca do bloco que uma automação ligada usa volta os nomes', :aggregate_failures do
      bloco.update!(ativa: true, ligada_por: admin)
      marcar(bloco, true)
      expect(response.parsed_body).to include('bloco' => true, 'ativa' => false)

      usa = automacao_ligada(account, admin, [{ 'id' => 'usar', 'tipo' => 'usar_bloco', 'bloco_id' => bloco.id }])
      marcar(bloco, false)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['problemas']).to eq([usa.nome])
      expect(bloco.reload.bloco).to be(true)
    end

    it 'sem a flag dos passos novos, não marca' do
      account.disable_features!('automacao_passos_novos')
      marcar(bloco, true)

      expect(bloco.reload.bloco).to be(false)
    end

    it 'marcar tira quem tinha ligado: o bloco nunca age por essa pessoa' do
      bloco.update!(ativa: true, ligada_por: admin)
      marcar(bloco, true)

      expect(bloco.reload.ligada_por).to be_nil
    end

    it 'o show do bloco diz quais automações ligadas por outra pessoa pausam quando quem pede salvar', :aggregate_failures do
      bloco.marcar_bloco!(true)
      usa = automacao_ligada(account, admin, [{ 'id' => 'usar', 'tipo' => 'usar_bloco', 'bloco_id' => bloco.id }])

      get "#{base}/#{bloco.id}", headers: com_funcao('automation_manage').create_new_auth_token, as: :json
      expect(response.parsed_body['bloco_pausaria']).to eq([usa.nome])

      get "#{base}/#{bloco.id}", headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['bloco_pausaria']).to eq([])
    end
  end

  describe 'GET historico com dentro=' do
    let(:inbox) { create_crm_whatsapp_api_inbox(account: account, members: [admin]) }
    let(:conversa) { create_crm_conversation(account: account, inbox: inbox, contact: account.contacts.create!(name: 'Ana')) }
    let(:bloco) do
      create(:autonomia_automacao, account: account, bloco: true).tap do |definicao|
        definicao.salvar_versao!(receita: { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [{ 'id' => 'b1', 'tipo' => 'parar' }] },
                                 autor: admin)
      end
    end
    let(:usa) { automacao_ligada(account, admin, [{ 'id' => 'usar', 'tipo' => 'usar_bloco', 'bloco_id' => bloco.id }]) }

    def dentro(automacao, filha_id) = get("#{base}/#{automacao.id}/historico", params: { dentro: filha_id }, headers: admin.create_new_auth_token)

    it 'abre a execução do bloco só para a automação que o usou, e só na conta', :aggregate_failures do
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(usa, conversa) }
      filha = Autonomia::Automacao::Execucao.find_by!(automacao: bloco)
      outra_conta = create(:autonomia_automacao_execucao, evento: "bloco:#{filha.id}:1:usar")

      dentro(usa, filha.id)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['execucoes'].first['passos'].pluck('passo')).to include('b1')

      dentro(automacao_ligada(account, admin, [{ 'id' => 'p', 'tipo' => 'parar' }]), filha.id)
      expect(response).to have_http_status(:not_found)

      dentro(usa, outra_conta.id)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET show: o endereço do "buscar em outro sistema"' do
    def consulta(id)
      { 'id' => id, 'tipo' => 'consultar', 'fonte' => { 'de' => 'endereco', 'url' => url },
        'guardar' => [{ 'nome' => 'Status', 'caminho' => 'status' }] }
    end

    it 'sai mascarado para quem não tem a chave de integrações, também nos galhos', :aggregate_failures do
      account.labels.create!(title: 'vip')
      lista = { 'id' => 'lista', 'tipo' => 'repetir_lista', 'lista' => { 'de' => 'etiqueta', 'etiqueta' => 'vip' }, 'teto' => 5,
                'ritmo' => 'rapido', 'cada' => [consulta('na_lista')] }
      definicao = automacao_ligada(account, admin, [consulta('fora').merge('nao_consultou' => [consulta('no_galho')]), lista])

      get "#{base}/#{definicao.id}", headers: com_funcao('automation_view').create_new_auth_token, as: :json
      receita = response.parsed_body.dig('versao', 'receita').to_json
      expect(receita).not_to include('token=abc')
      expect(receita.scan('https://loja.exemplo.com/•••').size).to eq(3)

      get "#{base}/#{definicao.id}", headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body.dig('versao', 'receita').to_json.scan('token=abc').size).to eq(3)
    end
  end
end

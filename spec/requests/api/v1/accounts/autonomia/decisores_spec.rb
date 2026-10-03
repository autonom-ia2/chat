require 'rails_helper'

RSpec.describe 'Decisores API', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:base) { "/api/v1/accounts/#{account.id}/autonomia/decisores" }
  let(:jev_url) { 'https://api.typesafe.ai/v1/systemone' }
  let(:corpo) do
    { nome: 'É lead?', pergunta: 'Este e-mail é de alguém querendo seguro?', instrucoes: 'Newsletter nunca é lead.',
      certeza_minima: 0.85,
      respostas: [{ chave: 'sim', descricao: 'Pede cotação' }, { chave: 'nao', descricao: 'Newsletter ou fornecedor' }] }
  end

  before { allow(TypesafeAi::Config).to receive_messages(api_key: 'ts_test_key_not_real', model: 'jev-1.13.0') }

  def agente_com(permissoes)
    agente = create(:user, account: account, role: :agent)
    agente.account_users.find_by(account: account).update!(custom_role: create(:custom_role, account: account, permissions: permissoes))
    agente
  end

  def conversa_com(texto, inbox: create(:inbox, account: account))
    conversation = create(:conversation, account: account, inbox: inbox)
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: texto)
    conversation
  end

  describe 'CRUD' do
    it 'cria, lê, lista, muda e apaga' do
      post base, params: corpo, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)
      id = response.parsed_body['id']
      expect(response.parsed_body).to include('nome' => 'É lead?', 'certeza_minima' => 0.85, 'instrucoes' => 'Newsletter nunca é lead.')

      patch "#{base}/#{id}", params: { instrucoes: 'Fornecedor não é lead.' }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['instrucoes']).to eq('Fornecedor não é lead.')

      get base, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['decisores'].first).to include('id' => id, 'esperando_pessoa' => 0)

      delete "#{base}/#{id}", headers: admin.create_new_auth_token, as: :json
      expect(Autonomia::Decisor.exists?(id)).to be(false)
    end

    it 'recusa respostas inválidas com a mensagem da validação' do
      post base, params: corpo.merge(respostas: [{ chave: 'sim', descricao: 'x' }]), headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('between 2 and 8')
    end

    it 'não mostra Decisor de outra conta' do
      de_outra = create(:autonomia_decisor)

      get "#{base}/#{de_outra.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'permissões' do
    let(:decisor) { create(:autonomia_decisor, account: account) }

    it 'agente sem função é recusado até na leitura' do
      get base, headers: create(:user, account: account, role: :agent).create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'automation_view lê mas não cria nem testa' do
      agente = agente_com(['automation_view'])

      get "#{base}/#{decisor.id}", headers: agente.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)

      post base, params: corpo, headers: agente.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      post "#{base}/#{decisor.id}/teste", params: {}, headers: agente.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'automation_manage cria' do
      post base, params: corpo, headers: agente_com(['automation_manage']).create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
    end
  end

  describe 'POST teste' do
    let(:decisor) { create(:autonomia_decisor, account: account) }
    let(:inbox) { create(:inbox, account: account) }

    before do
      stub_request(:post, jev_url).to_return(
        status: 200,
        body: { model: 'jev-1.13.0', usage: { input_tokens: 500, output_tokens: 1 },
                answers: { decisao: { type: 'choice', choice: 'sim', confidence: 0.9 } } }.to_json
      )
    end

    it 'responde nas conversas da caixa sem gravar decisão nem exemplo' do
      conversa_com('Quero cotar seguro auto', inbox: inbox)
      conversa_com('Newsletter da semana')

      post "#{base}/#{decisor.id}/teste", params: { inbox_id: inbox.id, quantidade: 5 }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      corpo = response.parsed_body
      expect(corpo).to include('testados' => 1, 'pedidos' => 1)
      expect(corpo['resultados'].first).to include('resposta' => 'sim', 'certeza' => 0.9, 'duvida' => false, 'trecho' => 'Quero cotar seguro auto')
      expect(corpo['resumo']).to eq('total' => 1, 'por_resposta' => { 'sim' => 1 }, 'duvidas' => 0)
      expect(Autonomia::DecisorDecisao.count).to eq(0)
      expect(decisor.reload.exemplos).to be_empty
    end

    it 'devolve o parcial quando o prazo de 10 s estoura' do
      3.times { |i| conversa_com("caso #{i}", inbox: inbox) }
      tempos = [0.0, 0.1, 9.5, 9.6].each
      relogio = -> { tempos.next }
      allow(Autonomia::Decisores::Teste).to receive(:new).and_wrap_original do |original, **args|
        original.call(**args, relogio: relogio)
      end

      post "#{base}/#{decisor.id}/teste", params: { inbox_id: inbox.id }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body).to include('testados' => 1, 'pedidos' => 3)
    end

    it 'deixa de fora a conversa sem texto, sem perguntar ao Jev' do
      conversa_com(nil, inbox: inbox)

      post "#{base}/#{decisor.id}/teste", params: { inbox_id: inbox.id }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body).to include('testados' => 0, 'pedidos' => 0)
      expect(a_request(:post, jev_url)).not_to have_been_made
    end

    it 'não começa pergunta ao Jev sem tempo para o pior caso dela (conectar e ler)' do
      2.times { |i| conversa_com("caso #{i}", inbox: inbox) }
      tempos = [0.0, 0.1, 4.5].each
      relogio = -> { tempos.next }
      allow(Autonomia::Decisores::Teste).to receive(:new).and_wrap_original do |original, **args|
        original.call(**args, relogio: relogio)
      end

      post "#{base}/#{decisor.id}/teste", params: { inbox_id: inbox.id }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body).to include('testados' => 1, 'pedidos' => 2)
    end

    it 'mostra os campos que extrairia, sem gravar no contato' do
      decisor.update!(campos: [{ chave: 'nome', descricao: 'Nome', destino: 'contato.nome' }])
      conversation = conversa_com('Nome: Joana Lima', inbox: inbox)
      cliente = instance_double(Crm::Ai::ResponsesClient, create: { text: { nome: 'Joana Lima' }.to_json })
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k' }))
      allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)

      post "#{base}/#{decisor.id}/teste", params: { inbox_id: inbox.id }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['resultados'].first['campos']).to eq('nome' => 'Joana Lima')
      expect(Crm::Ai::ResponsesClient).to have_received(:new).with(hash_including(max_retries: 0))
      expect(conversation.contact.reload.name).not_to eq('Joana Lima')
    end
  end

  describe 'POST exemplos' do
    let(:decisor) { create(:autonomia_decisor, account: account) }

    it 'guarda a conversa confirmada como exemplo da pessoa' do
      conversation = conversa_com('Quero cotar seguro residencial')

      post "#{base}/#{decisor.id}/exemplos", params: { conversation_id: conversation.id, resposta: 'sim' },
                                             headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(decisor.reload.exemplos.last).to include('texto' => 'Quero cotar seguro residencial', 'resposta' => 'sim', 'origem' => 'pessoa')
    end

    it 'recusa resposta que o Decisor não tem' do
      post "#{base}/#{decisor.id}/exemplos", params: { conversation_id: conversa_com('oi').id, resposta: 'talvez' },
                                             headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('sim, nao')
    end
  end

  describe 'casos parados' do
    let(:decisor) { create(:autonomia_decisor, account: account) }
    let(:conversation) { conversa_com('Talvez eu precise de seguro') }
    let(:rule) do
      create(:automation_rule, account: account,
                               event_name: 'message_created',
                               conditions: [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['open'], query_operator: nil }],
                               actions: [{ action_name: 'perguntar_ao_decisor', action_params: [decisor.id, 'sim'] },
                                         { action_name: 'add_label', action_params: ['lead'] }])
    end
    let!(:decisao) do
      create(:autonomia_decisor_decisao, decisor: decisor, conversation: conversation, message: conversation.messages.last,
                                         automation_rule: rule, esperas: [{ 'regra' => rule.id, 'indice' => 0 }],
                                         status: 'esperando_pessoa', certeza: 0.5)
    end

    it 'lista os casos esperando a pessoa' do
      get "#{base}/#{decisor.id}/decisoes", params: { status: 'esperando_pessoa' }, headers: admin.create_new_auth_token

      expect(response.parsed_body['decisoes'].map { |item| item['id'] }).to eq([decisao.id])
      expect(response.parsed_body['decisoes'].first['vence_em']).to be_present
    end

    it 'resolver vira exemplo e retoma a automação quando a resposta é a que segue' do
      headers = admin.create_new_auth_token
      perform_enqueued_jobs(only: Autonomia::Decisores::PerguntarJob) do
        post "/api/v1/accounts/#{account.id}/autonomia/decisoes/#{decisao.id}/resolver", params: { resposta: 'sim' },
                                                                                         headers: headers, as: :json
      end

      expect(response.parsed_body).to include('status' => 'resolvida', 'retomou' => true)
      expect(decisor.reload.exemplos.last).to include('origem' => 'pessoa', 'resposta' => 'sim')
      expect(conversation.reload.label_list).to eq(['lead'])
      expect(a_request(:post, jev_url)).not_to have_been_made
    end

    it 'duplo clique retoma a automação uma vez só' do
      headers = admin.create_new_auth_token
      url = "/api/v1/accounts/#{account.id}/autonomia/decisoes/#{decisao.id}/resolver"

      expect do
        2.times { post url, params: { resposta: 'sim' }, headers: headers, as: :json }
      end.to have_enqueued_job(Autonomia::Decisores::PerguntarJob).exactly(:once)

      expect(response.parsed_body).to include('status' => 'resolvida', 'retomou' => false)
      expect(decisor.reload.correcoes_count).to eq(0)
    end

    it 'caso de conversa sem texto pode ser resolvido' do
      conversation.messages.last.update!(content: nil)

      post "/api/v1/accounts/#{account.id}/autonomia/decisoes/#{decisao.id}/resolver", params: { resposta: 'sim' },
                                                                                       headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body).to include('status' => 'resolvida', 'retomou' => true)
      expect(decisor.reload.exemplos).to be_empty
    end

    it 'caso vencido vira exemplo mas não retoma' do
      headers = admin.create_new_auth_token
      travel_to(3.days.from_now) do
        post "/api/v1/accounts/#{account.id}/autonomia/decisoes/#{decisao.id}/resolver", params: { resposta: 'sim' },
                                                                                         headers: headers, as: :json
      end

      expect(response.parsed_body).to include('status' => 'vencida', 'retomou' => false)
      expect(decisor.reload.exemplos.size).to eq(1)
    end

    it 'corrigir decisão já tomada soma correção e não retoma' do
      decisao.update!(status: 'decidida_pelo_guia', resposta: 'sim')

      expect do
        post "/api/v1/accounts/#{account.id}/autonomia/decisoes/#{decisao.id}/resolver", params: { resposta: 'nao' },
                                                                                         headers: admin.create_new_auth_token, as: :json
      end.not_to have_enqueued_job(Autonomia::Decisores::PerguntarJob)

      expect(decisor.reload.correcoes_count).to eq(1)
      expect(decisao.reload).to have_attributes(status: 'resolvida', resposta: 'nao', resolvida_por_id: admin.id)
    end
  end
end

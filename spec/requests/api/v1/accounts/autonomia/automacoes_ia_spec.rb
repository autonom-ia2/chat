require 'rails_helper'

# A IA das automações pela tela (#2500 C2): o "Testar este passo" e os custos. O modelo é a OpenAI simulada no HTTP.
RSpec.describe 'Api::V1::Accounts::Autonomia::AutomacoesIa', :automacao_motor, type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/autonomia/automacoes" }
  let(:inbox) { create(:inbox, account: account) }
  let(:contato) { create(:contact, account: account, name: 'Bruno', email: 'bruno@exemplo.com', phone_number: '+5511999990000') }
  let!(:conversa) { create(:conversation, account: account, inbox: inbox, contact: contato, last_activity_at: 1.minute.ago) }
  let(:corpos) { [] }
  let(:le) { %w[mensagens_recentes] }
  let(:decidir) do
    { id: 'p1', tipo: 'decidir', le: le, pergunta: 'Sobre o que é?', nenhum: [],
      caminhos: [{ nome: 'Sinistro', chave: 'sinistro', descricao: 'bateu o carro', passos: [] },
                 { nome: 'Cotação', chave: 'cotacao', descricao: 'quer preço', passos: [] }] }
  end
  let(:receita) { { gatilho: { tipo: 'conversa.criada' }, passos: [decidir] } }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_editor', 'automacao_ia')
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-de-teste' })
    create(:message, conversation: conversa, account: account, message_type: :incoming, content: 'Bati o carro ontem')
  end

  def com_funcao(permissoes, caixa: inbox)
    create(:user, account: account, role: :agent).tap do |pessoa|
      create(:inbox_member, user: pessoa, inbox: caixa)
      pessoa.account_users.find_by(account: account).update!(custom_role: create(:custom_role, account: account, permissions: permissoes))
    end
  end

  def openai_devolve(resposta)
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return do |request|
      corpos << JSON.parse(request.body)
      payload = { id: "resp_#{corpos.size}", output_text: resposta.to_json, usage: { input_tokens: 1000, output_tokens: 200 } }
      { status: 200, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def testar(quem: admin, passo_id: 'p1', conversa_id: nil, corpo: receita)
    post "#{base}/testar_passo", params: { receita: corpo, passo_id: passo_id, conversa_id: conversa_id }.compact,
                                 headers: quem.create_new_auth_token, as: :json
  end

  describe 'POST testar_passo' do
    before { openai_devolve({ caminho: 'sinistro', motivo: 'O cliente bateu o carro.' }) }

    it 'roda o passo do rascunho numa conversa que entraria e mostra o que faria', :aggregate_failures do
      testar

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('candidatas' => [conversa.display_id], 'aviso' => nil)
      expect(response.parsed_body['conversa']).to include(
        'conversa_id' => conversa.display_id, 'nome' => 'Bruno',
        'resultado' => { 'caminho' => 'sinistro', 'motivo' => 'O cliente bateu o carro.' }
      )
      expect(response.parsed_body['conversa']['custo_usd']).to be_a(Numeric)
      expect(corpos.size).to eq(1)
    end

    it 'não grava nada além do uso da IA (e o aviso dele à Gestão IA), não transmite', :aggregate_failures do
      contagens = -> { [Message.count, Note.count, Autonomia::Automacao::Execucao.count, Autonomia::Automacao::Registro.count] }
      antes = contagens.call
      allow(ActionCable.server).to receive(:broadcast)

      admin
      clear_enqueued_jobs

      expect { testar }.to change(Crm::AiUsageEvent.where(feature: 'automacao_testar'), :count).by(1)

      expect(enqueued_jobs.pluck(:job)).to eq([Crm::Ai::UsageBroadcastJob])

      expect(contagens.call).to eq(antes)
      expect(ActionCable.server).not_to have_received(:broadcast)
    end

    it 'o que a IA respondeu não vai para o log', :aggregate_failures do
      openai_devolve({ caminho: 'sinistro', motivo: 'MOTIVO-SO-NA-TELA' })
      %i[debug info warn error].each { |nivel| allow(Rails.logger).to receive(nivel).and_call_original }

      testar

      expect(response.parsed_body.dig('conversa', 'resultado', 'motivo')).to eq('MOTIVO-SO-NA-TELA')
      %i[debug info warn error].each do |nivel|
        expect(Rails.logger).not_to have_received(nivel).with(a_string_including('MOTIVO-SO-NA-TELA'))
      end
    end

    it 'a IA que trava: 12 s, uma ida só, e a tela recebe "não respondeu" em vez de erro (Rack::Timeout, 15 s)', :aggregate_failures do
      stub_request(:post, 'https://api.openai.com/v1/responses').to_timeout
      allow(HTTParty).to receive(:post).and_call_original

      testar

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['conversa']).to include('motivo' => 'ia_indisponivel')
      expect(HTTParty).to have_received(:post).once.with(a_string_including('/v1/responses'), hash_including(timeout: 12, max_retries: 0))
    end

    it 'sem financial_view, mostra o resultado e não o custo' do
      testar(quem: com_funcao(%w[automation_manage conversation_manage]))

      expect(response).to have_http_status(:ok)

      expect(response.parsed_body['conversa']).to include('resultado')
      expect(response.parsed_body['conversa']).not_to have_key('custo_usd')
    end

    it 'com financial_view, mostra o custo' do
      testar(quem: com_funcao(%w[automation_manage conversation_manage financial_view]))

      expect(response.parsed_body['conversa']).to include('custo_usd')
    end

    it 'recusa quem só vê automações, sem chamar a IA' do
      testar(quem: com_funcao(%w[automation_view]))

      expect(response).to have_http_status(:unauthorized)
      expect(corpos).to be_empty
    end

    it 'sem a flag da F7 ou do editor, é como se não existisse', :aggregate_failures do
      account.disable_features!('automacao_ia')
      testar
      expect(response).to have_http_status(:not_found)

      account.enable_features!('automacao_ia')
      account.disable_features!('automacao_editor')
      testar
      expect(response).to have_http_status(:not_found)
      expect(corpos).to be_empty
    end

    it 'o extrair não se testa: gravar é o que ele faz', :aggregate_failures do
      extrair = { id: 'p1', tipo: 'extrair', le: le, campos: [{ chave: 'placa', descricao: 'a placa', destino: 'conversa.atributos.placa' }] }
      create(:custom_attribute_definition, account: account, attribute_key: 'placa', attribute_model: 'conversation_attribute')

      testar(corpo: receita.merge(passos: [extrair]))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.automacao.testar.passo_nao_testavel', locale: :pt_BR))
      expect(corpos).to be_empty
    end

    it 'o rascunho com problema volta em frase, antes de qualquer chamada', :aggregate_failures do
      testar(corpo: receita.merge(passos: [decidir.merge(caminhos: [])]))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['problemas']).to be_present
      expect(corpos).to be_empty
    end

    it 'sem a chave da própria conta, não testa' do
      Integrations::Hook.where(account: account).destroy_all

      testar

      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.automacao.testar.ia_nao_configurada', locale: :pt_BR))
    end

    it 'só usa conversas que quem pede enxerga: de outra caixa, não há o que testar', :aggregate_failures do
      testar(quem: com_funcao(%w[automation_manage], caixa: create(:inbox, account: account)))

      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.automacao.testar.sem_conversa', locale: :pt_BR))
      expect(corpos).to be_empty
    end

    it 'o 1º pedido escolhe até 3 e devolve os ids; os seguintes mandam o id escolhido', :aggregate_failures do
      3.times { create(:message, conversation: create(:conversation, account: account, inbox: inbox), account: account, content: 'oi') }

      testar
      candidatas = response.parsed_body['candidatas']
      expect(candidatas.size).to eq(3)
      expect(response.parsed_body['conversa']['conversa_id']).to eq(candidatas.first)

      testar(conversa_id: candidatas.second)
      expect(response.parsed_body).to eq('conversa' => response.parsed_body['conversa'])
      expect(response.parsed_body['conversa']['conversa_id']).to eq(candidatas.second)
      expect(corpos.size).to eq(2)
    end

    it 'id de conversa que quem pede não enxerga é 404, sem chamar a IA', :aggregate_failures do
      alheia = create(:conversation, account: account, inbox: create(:inbox, account: account))
      pessoa = com_funcao(%w[automation_manage conversation_manage])

      expect { testar(quem: pessoa, conversa_id: alheia.display_id) }.not_to change(Crm::AiUsageEvent, :count)

      expect(response).to have_http_status(:not_found)
      expect(corpos).to be_empty
    end

    # O Rack::Timeout corta aos 15 s e a IA tem 12. O resto do pedido é preso por uma conta fixa de consultas, não pelo
    # relógio (que oscila com a máquina): hoje são 23. O tempo largo fica só de alarme.
    it 'fora a chamada à IA, o pedido faz poucas consultas e não se aproxima do corte', :aggregate_failures do
      testar
      consultas = 0
      contar = ->(*, dados) { consultas += 1 unless dados[:name] == 'SCHEMA' || dados[:cached] }
      tempo = ActiveSupport::Notifications.subscribed(contar, 'sql.active_record') do
        Benchmark.realtime { testar(conversa_id: conversa.display_id) }
      end

      expect(consultas).to be <= 30
      expect(tempo).to be < 5.0
    end

    it 'nenhuma conversa entraria: testa nas recentes e avisa' do
      resolvida = { campo: { '$valor': 'conversa.status' }, op: 'igual', valor: 'resolved' }
      testar(corpo: receita.merge(gatilho: { tipo: 'conversa.criada', filtros: [resolvida] }))

      expect(response.parsed_body).to include('aviso' => 'nenhuma_entraria', 'candidatas' => [conversa.display_id])
    end
  end

  it 'o card nunca vai à IA: o esquema da receita não aceita card em le' do
    testar(corpo: receita.merge(passos: [decidir.merge(le: %w[mensagens_recentes card])]))

    expect(response).to have_http_status(:unprocessable_entity)
    expect(corpos).to be_empty
  end

  describe 'custos' do
    let(:automacao) { create(:autonomia_automacao, account: account) }
    let(:versao) { create(:autonomia_automacao_versao, automacao: automacao) }

    before do
      execucao = create(:autonomia_automacao_execucao, versao: versao, alvo: conversa)
      [0.002, 0.004].each do |custo|
        create(:autonomia_automacao_registro, execucao: execucao, passo: 'p1', dados: { 'ia' => { 'custo_usd' => custo } })
      end
      create(:autonomia_automacao_registro, execucao: execucao, passo: 'p2', dados: { 'ramo' => 'entao' })
      travel_to(31.days.ago) { create(:autonomia_automacao_registro, execucao: execucao, passo: 'p1', dados: { 'ia' => { 'custo_usd' => 9.0 } }) }
    end

    it 'a lista leva a soma dos últimos 30 dias de cada automação' do
      get "#{base}/custos", headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['custos']).to eq(automacao.id.to_s => 0.006)
    end

    it 'o cartão leva a média por passo e quantas vezes' do
      get "#{base}/#{automacao.id}/custos", headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['custos']).to eq('p1' => { 'media' => 0.003, 'vezes' => 2 })
    end

    it 'sem financial_view, volta vazio: é dinheiro da conta (#1969)', :aggregate_failures do
      leitor = com_funcao(%w[automation_view])

      get "#{base}/custos", headers: leitor.create_new_auth_token, as: :json
      expect(response.parsed_body).to eq('com_valores' => false, 'custos' => {})

      get "#{base}/#{automacao.id}/custos", headers: leitor.create_new_auth_token, as: :json
      expect(response.parsed_body['custos']).to eq({})
    end

    it 'com financial_view, mostra; a de outra conta é 404', :aggregate_failures do
      get "#{base}/custos", headers: com_funcao(%w[automation_view financial_view]).create_new_auth_token, as: :json
      expect(response.parsed_body['custos']).to eq(automacao.id.to_s => 0.006)

      get "#{base}/#{create(:autonomia_automacao).id}/custos", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end

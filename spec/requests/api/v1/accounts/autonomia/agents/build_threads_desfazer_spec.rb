require 'rails_helper'

# #1428 (tema 6, parte 3) — o resultado do ajuste no GET da conversa e o POST de Desfazer, só no piloto.
RSpec.describe 'Autonomia build threads: resultado e desfazer', type: :request do
  let(:account) { conta_da_fase2 }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Hubber', agent_type: 'support', mode: :guided,
                                     instruction: 'Instrução antiga.', scaffold: 'andaime antigo', tone: 'cordial',
                                     config: { 'guardrails' => ['Não invente.'], 'model' => 'gpt-x' })
  end
  let(:thread) { Autonomia::Agents::BuildThread.create!(account: account, agent: agent, created_by: administrator) }
  let(:url) { "/api/v1/accounts/#{account.id}/autonomia/build_threads/#{thread.id}" }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run }
  end

  # Um ajuste aplicado pelo Construtor (com as versões de verdade) e o fechamento no state, como o Builder deixa.
  before do
    token = thread.begin_build!
    agent.apply_builder_config!(token, { instruction: 'Instrução nova.', tone: 'curto' })
    itens = [{ 'campo' => 'tone', 'pedido' => 'mais curto', 'resumo' => 'Respostas curtas.', 'atendido' => true,
               'pedido_pelo_dono' => true }]
    ultimo = { 'versao_antes_id' => agent.versao_antes_do_construtor.id, 'versao_id' => agent.versao_do_construtor.id,
               'conferencia' => { 'itens' => itens } }
    thread.mark_ready!(token, state: { 'applied' => true, 'conferencia' => { 'itens' => itens }, 'ultimo_ajuste' => ultimo })
  end

  def desfazer
    post "#{url}/desfazer", headers: administrator.create_new_auth_token, as: :json
  end

  describe 'GET /autonomia/build_threads/:id' do
    it 'traz o resultado sem o campo, a instrução nem o andaime' do
      get url, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('payload', 'state', 'resultado')).to include(
        'itens' => [{ 'estado' => 'aplicado', 'texto' => 'Respostas curtas.' }], 'pode_desfazer' => true, 'desfeito' => false
      )
      expect(response.body).not_to include('campo', 'Instrução', 'andaime', 'ultimo_ajuste', 'versao_antes_id')
    end

    # #1428 (entrega C) — as respostas prontas da pergunta aberta.
    it 'traz as opções de resposta da pergunta aberta' do
      thread.update!(state: thread.state.merge('opcoes_de_resposta' => ['Manter assim', 'Quero mudar']))

      get url, headers: administrator.create_new_auth_token, as: :json

      expect(response.parsed_body.dig('payload', 'state', 'opcoes_de_resposta')).to eq(['Manter assim', 'Quero mudar'])
    end

    it 'com o piloto desligado no meio da conversa, não traz as opções que ficaram no state' do
      thread.update!(state: thread.state.merge('opcoes_de_resposta' => ['Manter assim', 'Quero mudar']))
      Autonomia::Agents::Fase2.desligar!(account)

      get url, headers: administrator.create_new_auth_token, as: :json

      expect(response.parsed_body.dig('payload', 'state')).not_to have_key('opcoes_de_resposta')
    end

    it 'sem a chave no state (fora do piloto), não traz opções' do
      get url, headers: administrator.create_new_auth_token, as: :json

      expect(response.parsed_body.dig('payload', 'state')).not_to have_key('opcoes_de_resposta')
    end

    it 'fora do piloto não traz o resultado' do
      Autonomia::Agents::Fase2.desligar!(account)

      get url, headers: administrator.create_new_auth_token, as: :json

      expect(response.parsed_body.dig('payload', 'state')).not_to have_key('resultado')
    end

    # #1428 (entrega B) — as perguntas de prova vão dentro do resultado: a pergunta do cliente e a resposta do agente.
    describe 'a prova' do
      def com_prova(prova)
        versao = thread.reload.state.dig('ultimo_ajuste', 'versao_id')
        thread.update!(state: thread.state.merge('prova' => { 'versao_id' => versao, 'desde' => Time.current.iso8601 }.merge(prova)))
        get url, headers: administrator.create_new_auth_token, as: :json
        response.parsed_body.dig('payload', 'state', 'resultado', 'prova')
      end

      it 'pendente: só o status e quantas perguntas' do
        expect(com_prova('status' => 'pendente', 'perguntas' => [{ 'pergunta' => 'Quanto custa?' }]))
          .to eq('status' => 'pendente', 'total' => 1)
      end

      it 'pronta: o placar e cada pergunta com a resposta, sem versão, data, campo, instrução nem andaime' do
        prova = com_prova('status' => 'pronta', 'ok' => 1, 'total' => 1,
                          'perguntas' => [{ 'pergunta' => 'Quanto custa?', 'resposta' => 'Passo para a equipe.', 'equipe' => false,
                                            'veredito' => 'ok' }])

        expect(prova).to eq('status' => 'pronta', 'ok' => 1, 'total' => 1, 'completa' => true,
                            'perguntas' => [{ 'pergunta' => 'Quanto custa?', 'resposta' => 'Passo para a equipe.', 'equipe' => false,
                                              'ok' => true }])
        expect(response.body).not_to include('versao_id', 'desde', 'veredito', 'campo', 'Instrução', 'andaime')
      end

      # #1428 (t6, cartão aprovado pelo Rodrigo em 22/10): a prova incompleta diz quais pedidos ficaram sem teste.
      it 'pronta e incompleta: os textos dos pedidos sem teste, sem campo, instrução nem os testes gravados' do
        prova = com_prova('status' => 'pronta', 'ok' => 0, 'total' => 0, 'completa' => false,
                          'perguntas' => [{ 'pergunta' => 'Quanto custa?', 'resposta' => 'Passo para a equipe.', 'equipe' => true,
                                            'testes' => [] }])

        expect(prova).to include('completa' => false, 'pedidos_sem_teste' => ['mais curto'])
        expect(response.body).not_to include('testes', 'campo', 'tone', 'Instrução', 'andaime')
      end

      it 'depois do Desfazer, sem prova' do
        versao = thread.state.dig('ultimo_ajuste', 'versao_id')
        thread.update!(state: thread.state.merge('prova' => { 'status' => 'pendente', 'versao_id' => versao }))
        desfazer

        expect(response.parsed_body.dig('payload', 'state', 'resultado')).to include('desfeito' => true, 'prova' => nil)
      end
    end
  end

  # A faixa "Última mudança" da tela nova (depois do RESET ou de recarregar): vem no GET do agente.
  describe 'GET /autonomia/agents/:id (ultima_mudanca_desfazivel)' do
    def ultima_mudanca
      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}", headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      response.parsed_body['ultima_mudanca_desfazivel']
    end

    it 'traz a conversa e os resumos do que entrou, sem campo, instrução nem andaime' do
      expect(ultima_mudanca).to eq('thread_id' => thread.id, 'linhas' => ['Respostas curtas'], 'sem_pedido' => [])
      expect(response.body).not_to include('campo', 'Instrução', 'andaime', 'ultimo_ajuste', 'versao_antes_id')
    end

    it 'some quando o agente muda por outro caminho' do
      agent.update!(greeting: 'Editado à mão.')

      expect(ultima_mudanca).to be_nil
    end

    it 'some depois de desfeito' do
      post "#{url}/desfazer", headers: administrator.create_new_auth_token, as: :json

      expect(ultima_mudanca).to be_nil
    end

    it 'continua depois de abrir uma conversa nova, de ligar e de desligar' do
      Autonomia::Agents::BuildThread.create!(account: account, agent: agent, created_by: administrator, status: :ready)
      agent.update!(enabled: false)
      agent.update!(enabled: true)

      expect(ultima_mudanca).to eq('thread_id' => thread.id, 'linhas' => ['Respostas curtas'], 'sem_pedido' => [])
    end

    it 'continua enquanto outra conversa gera; o Desfazer cancela esse pedido' do
      outra = Autonomia::Agents::BuildThread.create!(account: account, agent: agent, created_by: administrator)
      outra.begin_build!
      expect(ultima_mudanca).to include('thread_id' => thread.id)

      post "#{url}/desfazer", headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      get "/api/v1/accounts/#{account.id}/autonomia/build_threads/#{outra.id}", headers: administrator.create_new_auth_token, as: :json
      expect(response.parsed_body.dig('payload', 'state')).to include('error' => 'superada_pelo_desfazer')
    end

    it 'fora do piloto não vem' do
      Autonomia::Agents::Fase2.desligar!(account)

      expect(ultima_mudanca).to be_nil
    end

    it 'não vem em agente manual' do
      agent.update_columns(mode: Autonomia::Agents::Agent.modes[:manual]) # rubocop:disable Rails/SkipsModelValidations

      expect(ultima_mudanca).to be_nil
    end
  end

  describe 'POST /autonomia/build_threads/:id/desfazer' do
    it 'volta o agente à versão de antes e responde o resultado desfeito' do
      desfazer

      expect(response).to have_http_status(:ok)
      expect(agent.reload).to have_attributes(instruction: 'Instrução antiga.', tone: 'cordial', scaffold: 'andaime antigo')
      expect(agent.config).to include('guardrails' => ['Não invente.'], 'model' => 'gpt-x')
      expect(response.parsed_body.dig('payload', 'state', 'resultado')).to include('desfeito' => true, 'pode_desfazer' => false)
      expect(response.body).not_to include('Instrução', 'andaime', 'campo')
    end

    it 'tira as respostas prontas da pergunta: ela não vale mais' do
      thread.update!(state: thread.state.merge('opcoes_de_resposta' => ['Manter assim', 'Quero mudar']))

      desfazer

      expect(response).to have_http_status(:ok)
      expect(thread.reload.state).not_to have_key('opcoes_de_resposta')
      expect(response.parsed_body.dig('payload', 'state')).not_to have_key('opcoes_de_resposta')
    end

    it 'pedir de novo responde 200 sem versão nova' do
      desfazer

      expect { desfazer }.not_to(change { agent.instruction_versions.count })
      expect(response).to have_http_status(:ok)
    end

    it '409 quando o agente mudou depois do ajuste' do
      agent.update!(greeting: 'Editado à mão.')

      desfazer

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to include('code' => 'agente_mudou',
                                              'error' => I18n.t('autonomia.build_thread.ajuste_mudou'))
      expect(agent.reload.tone).to eq('curto')
    end

    it '422 com agente manual' do
      agent.update_columns(mode: Autonomia::Agents::Agent.modes[:manual]) # rubocop:disable Rails/SkipsModelValidations

      desfazer

      expect(response).to have_http_status(:unprocessable_entity)
      expect(agent.reload.tone).to eq('curto')
    end

    it '422 com o Agente de Cotação' do
      agent.update_columns(agent_type: 'insurance_quote') # rubocop:disable Rails/SkipsModelValidations

      desfazer

      expect(response).to have_http_status(:unprocessable_entity)
      expect(agent.reload.tone).to eq('curto')
    end

    it '409 com o texto de tentar de novo quando duas escritas se travam (Deadlocked), não 500' do
      allow_any_instance_of(Autonomia::Agents::Agent).to receive(:desfazer_ajuste!).and_raise(ActiveRecord::Deadlocked) # rubocop:disable RSpec/AnyInstance

      desfazer

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to include('code' => 'conflito_de_trava', 'error' => I18n.t('autonomia.agents.conflito_de_trava'))
    end

    it 'a volta por Versões também responde 409 num Deadlocked' do
      allow_any_instance_of(Autonomia::Agents::Agent).to receive(:restore_instruction!).and_raise(ActiveRecord::Deadlocked) # rubocop:disable RSpec/AnyInstance

      post "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/instruction_versions/#{agent.instruction_versions.first.id}/restore",
           headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['code']).to eq('conflito_de_trava')
    end

    it 'o retry de um pedido cancelado pelo Desfazer é recusado (pedir de novo escrevendo)' do
      outra = Autonomia::Agents::BuildThread.create!(account: account, agent: agent, created_by: administrator)
      outra.begin_build!
      desfazer
      allow(Autonomia::Agents::Builder::SubmitJob).to receive(:perform_later)

      retry_url = "/api/v1/accounts/#{account.id}/autonomia/build_threads/#{outra.id}/retry"
      post retry_url, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.build_thread.pedir_de_novo'))
      expect(Autonomia::Agents::Builder::SubmitJob).not_to have_received(:perform_later)
    end

    it '404 fora do piloto' do
      Autonomia::Agents::Fase2.desligar!(account)

      desfazer

      expect(response).to have_http_status(:not_found)
      expect(agent.reload.tone).to eq('curto')
    end

    it '404 com conversa de criação (sem agente)' do
      criacao = Autonomia::Agents::BuildThread.create!(account: account, created_by: administrator)

      post "/api/v1/accounts/#{account.id}/autonomia/build_threads/#{criacao.id}/desfazer",
           headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it '404 com conversa de outra conta' do
      outra = conta_da_fase2
      alheia = Autonomia::Agents::BuildThread.create!(account: outra)

      post "/api/v1/accounts/#{account.id}/autonomia/build_threads/#{alheia.id}/desfazer",
           headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end

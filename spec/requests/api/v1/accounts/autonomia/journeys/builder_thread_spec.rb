require 'rails_helper'

# Jornada "caminhos tristes" do Construtor (BuildThreads): thread inexistente/de outra
# conta, thread cujo agente foi deletado e mensagem em branco. Documenta o comportamento
# ATUAL (dependent: :nullify mantém a thread viva sem agente).
RSpec.describe 'Autonomia journeys - builder threads', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  def create_agent
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Agente Construido', agent_type: 'support', mode: :guided,
      status: :draft, enabled: false, actuation: :external
    )
  end

  def post_message(thread_id, message: 'Quero um agente de suporte')
    post "/api/v1/accounts/#{account.id}/autonomia/build_threads/#{thread_id}/messages",
         params: { message: message },
         headers: administrator.create_new_auth_token, as: :json
  end

  # #380 (rodada de correção) — o "Ajustar com IA" do PanelTune abre uma thread do Construtor para o
  # agente e, no fechamento, `apply_builder_config!` reescreve instruction/scaffold/config. A instrução
  # do Agente de Cotação é mantida pela Autonom.ia: a porta recusa antes de gastar modelo.
  it 'refuses to open a builder thread for the quote agent, whose instruction is maintained' do
    # Arrange
    lia = Autonomia::Insurance::QuoteAgent::Builder.new(account: account, nome_agente: 'Lia', nome_corretora: 'Sena').call

    # Act
    expect do
      post "/api/v1/accounts/#{account.id}/autonomia/build_threads",
           params: { autonomia_agent_id: lia.id, message: 'Ajusta o tom' },
           headers: administrator.create_new_auth_token, as: :json
    end.not_to change(Autonomia::Agents::BuildThread, :count)

    # Assert
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq(I18n.t('autonomia.agents.instrucao_mantida', raise: true))
  end

  # THREAD CRIADA ANTES DA GUARDA. O `create` recusa, mas uma thread vinculada à Lia antes do deploy
  # (alguém usou "Ajustar com IA" entre 08/09 e a subida) segue no banco; `messages` e `retry` não
  # passam por `thread_params`. Sem esta guarda o job rodava o modelo e só falhava no
  # `apply_builder_config!` — gasto de modelo e `build_error` genérico, sem a mensagem.
  describe 'a builder thread already bound to the quote agent' do
    let(:lia) { Autonomia::Insurance::QuoteAgent::Builder.new(account: account, nome_agente: 'Lia', nome_corretora: 'Sena').call }

    it 'refuses a new message before spending the model' do
      # Arrange
      thread = Autonomia::Agents::BuildThread.create!(account: account, agent: lia, status: :ready)

      # Act
      expect { post_message(thread.id, message: 'Ajusta o tom') }
        .not_to have_enqueued_job(Autonomia::Agents::Builder::SubmitJob)

      # Assert
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.agents.instrucao_mantida', raise: true))
      thread.reload
      expect(thread.messages).to be_blank
      expect(thread.status).to eq('ready')
    end

    it 'refuses the retry of a failed build before spending the model' do
      # Arrange
      thread = Autonomia::Agents::BuildThread.create!(account: account, agent: lia, status: :failed)

      # Act
      expect do
        post "/api/v1/accounts/#{account.id}/autonomia/build_threads/#{thread.id}/retry",
             headers: administrator.create_new_auth_token, as: :json
      end.not_to have_enqueued_job(Autonomia::Agents::Builder::SubmitJob)

      # Assert
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.agents.instrucao_mantida', raise: true))
      expect(thread.reload.status).to eq('failed')
    end
  end

  it 'returns 404 when posting a message to a nonexistent thread' do
    # Act
    post_message(999_999)

    # Assert
    expect(response).to have_http_status(:not_found)
  end

  it 'returns 404 when posting a message to a thread of another account' do
    # Arrange — thread pertence à conta B; o escopo build_threads_scope é por conta.
    other_account = create(:account, internal_attributes: { 'autonomia_agents_enabled' => true })
    foreign_thread = Autonomia::Agents::BuildThread.create!(account: other_account)

    # Act
    post_message(foreign_thread.id)

    # Assert — IDOR bloqueado: nem leitura nem escrita cross-account.
    expect(response).to have_http_status(:not_found)
    expect(foreign_thread.reload.messages).to be_blank
  end

  it 'keeps the thread alive (agent nulled) after the agent is deleted and still accepts messages' do
    # Arrange — thread ligada a um agente que é deletado em seguida.
    agent = create_agent
    thread = Autonomia::Agents::BuildThread.create!(account: account, agent: agent)
    agent.destroy!

    # Act — comportamento ATUAL: dependent: :nullify preserva a thread; a conversa do
    # Construtor continua e o Builder criará um rascunho novo se fechar de novo.
    post_message(thread.id, message: 'Continuar mesmo sem o agente')

    # Assert
    expect(response).to have_http_status(:accepted)
    thread.reload
    expect(thread.autonomia_agent_id).to be_nil
    expect(thread.messages.last['content']).to eq('Continuar mesmo sem o agente')
    expect(thread.status).to eq('processing')
  end

  it 'rejects a blank continuation message with 422' do
    # Arrange
    thread = Autonomia::Agents::BuildThread.create!(account: account, agent: create_agent)

    # Act
    post_message(thread.id, message: '')

    # Assert — o guard de mensagem em branco vale só na continuação (não na abertura).
    expect(response).to have_http_status(:unprocessable_entity)
    expect(thread.reload.messages).to be_blank
  end
end

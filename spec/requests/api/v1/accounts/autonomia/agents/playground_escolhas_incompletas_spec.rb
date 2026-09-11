require 'rails_helper'

# ESCOLHAS INCOMPLETAS NA API: RECUSA EXPLÍCITA, NÃO 500 (#380, rodada 4).
#
# A chave `agente_de_cotacao` do config presente e incompleta (só escrita fora do Builder produz isso) faz
# `Agent#instrucao_do_sistema` levantar `Builder::EscolhasIncompletas` na montagem do prompt. O Responder
# já registra isso (rodada 3); o Testar e o Copilot passam pelo MESMO `Answerer` e respondiam 500 genérico,
# sem o nome do campo e sem registro além do erro do Rails — recusa fechada, mas nem explícita nem
# registrada. Agora `Autonomia::BaseController` resgata na porta: 422 com código estável e o campo.
#
# O Answerer NÃO é dublado: o erro nasce no caminho real (`PromptBuilder#instructions`). Dublada é só a
# credencial, para o `generate` chegar à montagem do prompt; o que prova que o modelo não foi chamado é
# `create_with_tool_executor` (o `new` do cliente é avaliado antes dos argumentos, onde o erro nasce).
RSpec.describe 'Autonomia agent playground with incomplete quote-agent choices', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:chave) { Autonomia::Insurance::QuoteAgent::Builder::ESCOLHAS_DA_CORRETORA }
  let(:lia) { Autonomia::Insurance::QuoteAgent::Builder.new(account: account, nome_agente: 'Lia', nome_corretora: 'Sena').call }
  let(:cliente_de_ia) { instance_double(Crm::Ai::ResponsesClient, create_with_tool_executor: { text: '{}' }) }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  before do
    # Escrita fora do Builder: a chave fica sem `horario`.
    lia.update!(config: lia.config.merge(chave => lia.config[chave].except('horario')))
    resolver = instance_double(Crm::Ai::CredentialResolver, resolve: 'ai-credential')
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente_de_ia)
    allow(Rails.logger).to receive(:warn).and_call_original
  end

  shared_examples 'recusa explícita com o campo' do |acao|
    it "answers 422 with a stable code and the missing field on #{acao}, without calling the model" do
      # Act
      post "/api/v1/accounts/#{account.id}/autonomia/agents/#{lia.id}/#{acao}",
           params: { message: 'quero cotar meu carro' }, headers: administrator.create_new_auth_token, as: :json

      # Assert
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('code' => 'escolhas_incompletas', 'campo' => 'horario')
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.agents.escolhas_incompletas', campo: 'horario'))
      expect(response.parsed_body['error']).not_to include('Translation missing')
      expect(cliente_de_ia).not_to have_received(:create_with_tool_executor)
      expect(Rails.logger).to have_received(:warn).with(/escolhas_incompletas.*campo=horario/)
    end
  end

  describe 'POST .../agents/:id/test (Testar)' do
    it_behaves_like 'recusa explícita com o campo', 'test'
  end

  describe 'POST .../agents/:id/suggest (Copilot)' do
    it_behaves_like 'recusa explícita com o campo', 'suggest'
  end

  # O valor de outra escolha nunca sai na resposta: a mensagem do erro é só o nome do campo.
  it 'never echoes another choice in the body' do
    post "/api/v1/accounts/#{account.id}/autonomia/agents/#{lia.id}/test",
         params: { message: 'oi' }, headers: administrator.create_new_auth_token, as: :json

    expect(response.body).not_to include('Sena')
  end

  # A Lia com as quatro escolhas segue pelo caminho normal: a porta não recusa nada além do defeito, e o
  # modelo é chamado. O 200 da view NÃO é medido aqui: `test.json.jbuilder` chama `json.should`, que no
  # ambiente de teste colide com o `should` do RSpec (pré-existente, fora desta PR — registrado na
  # auditoria); o que esta spec prova é que a recusa só acontece com a chave incompleta.
  it 'does not refuse when the choices are complete, and calls the model' do
    lia.update!(config: lia.config.merge(chave => lia.config[chave].merge('horario' => 'todo dia')))

    post "/api/v1/accounts/#{account.id}/autonomia/agents/#{lia.id}/test",
         params: { message: 'oi' }, headers: administrator.create_new_auth_token, as: :json

    expect(response).not_to have_http_status(:unprocessable_entity)
    expect(cliente_de_ia).to have_received(:create_with_tool_executor)
  end
end

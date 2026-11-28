require 'rails_helper'

# #3211 (Tarefa 21) — a corretora troca os dados do agente contratado (nome do agente, nome e apresentação da corretora)
# pela API, e as recusas que o contratado recebe da instrução mantida o nomeiam como ele é, não como o Agente de Cotação
# (o texto da Lia não muda).
RSpec.describe 'Autonomia agente contratado: dados da corretora', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:outra_conta) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:agente_sem_funcao) { create(:user, account: account, role: :agent) }
  let(:marca) do
    { 'modelo' => 'seguro_viagem_universal', 'nome_agente' => 'Bia', 'nome_corretora' => 'Corretora Exemplo',
      'sobre_corretora' => 'Corretora de seguros desde 2010.' }
  end
  let(:agente) { contratado_em(account) }
  let(:tres_campos) { { nome_agente: 'Rita', nome_corretora: 'Corretora Nova', sobre_corretora: 'Seguros de viagem.' } }
  let(:agents_url) { "/api/v1/accounts/#{account.id}/autonomia/agents" }
  let(:contratado_url) { "#{agents_url}/#{agente.id}/contratado" }
  let(:outro_contratado_url) { "#{agents_url}/#{contratado_em(outra_conta).id}/contratado" }
  let(:texto_do_contratado) { I18n.t('autonomia.contratados.instrucao_mantida') }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  before do
    enable_test_encryption!
    [account, outra_conta].each do |conta|
      marcar_corretora!(conta)
      conta.enable_features!('agente_seguro_viagem_universal', 'agente_ferramentas_prontas', 'agente_ferramentas_prontas_consultas')
    end
  end

  def contratado_em(conta)
    Autonomia::Agents::Agent.create!(account: conta, name: 'Bia', agent_type: 'sdr', instruction: 'retrato do nascimento',
                                     config: { 'contratado' => marca })
  end

  # #3270: a página do agente lê o preço e o estado do período grátis em `contratado.plano` (o show e a listagem).
  describe 'GET agents/:id: o plano do contratado' do
    def plano_no_show
      get "#{agents_url}/#{agente.id}", headers: admin.create_new_auth_token, as: :json
      response.parsed_body.dig('contratado', 'plano')
    end

    it 'no grátis: os dias que faltam e o preço' do
      agente.update_columns(created_at: 3.days.ago) # rubocop:disable Rails/SkipsModelValidations

      expect(plano_no_show).to eq('dias_gratis' => 7, 'preco_mensal_centavos' => 19_700, 'moeda' => 'BRL',
                                  'situacao' => 'gratis', 'dias_restantes' => 4)
    end

    it 'pausado e, liberada a conta, liberado' do
      agente.update_columns(created_at: 8.days.ago) # rubocop:disable Rails/SkipsModelValidations
      expect(plano_no_show).to include('situacao' => 'pausado', 'dias_restantes' => nil)

      Autonomia::Agents::Contratados::Liberacao.atribuir(account, ['seguro_viagem_universal'])
      account.save!
      expect(plano_no_show).to include('situacao' => 'liberado', 'dias_restantes' => nil)
    end

    it 'na listagem também (a página pode ler o agente da lista)' do
      agente.update_columns(created_at: 8.days.ago) # rubocop:disable Rails/SkipsModelValidations

      get agents_url, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload'].find { |item| item['id'] == agente.id }.dig('contratado', 'plano', 'situacao')).to eq('pausado')
    end

    it 'agente comum: sem contratado' do
      comum = Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'sdr', instruction: 'x')

      get "#{agents_url}/#{comum.id}", headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['contratado']).to be_nil
    end
  end

  describe 'PATCH agents/:agent_id/contratado' do
    it 'troca os três dados e responde o agente' do
      patch contratado_url, params: tres_campos, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['name']).to eq('Rita')
      expect(response.parsed_body['contratado']).to include('modelo' => 'seguro_viagem_universal', 'nome_agente' => 'Rita',
                                                            'nome_corretora' => 'Corretora Nova', 'sobre_corretora' => 'Seguros de viagem.')
      expect(agente.reload.config['contratado']['nome_corretora']).to eq('Corretora Nova')
    end

    it 'agente de outra conta: 404' do
      patch outro_contratado_url, params: tres_campos, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'agente que não é contratado: 404' do
      comum = Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'sdr', instruction: 'x')

      patch "#{agents_url}/#{comum.id}/contratado", params: tres_campos, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(comum.reload.config).not_to include('contratado')
    end

    it 'recusa com o campo que a tela destaca (R14), sem mudar nada' do
      patch contratado_url, params: tres_campos.merge(sobre_corretora: 'Fale com $nomeCorretora'), headers: admin.create_new_auth_token,
                            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.slice('code', 'campo')).to eq('code' => 'marcador', 'campo' => 'sobre_corretora')
      expect(agente.reload.config['contratado']).to eq(marca)
    end

    it 'agente sem função não troca os dados' do
      patch contratado_url, params: tres_campos, headers: agente_sem_funcao.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(agente.reload.name).to eq('Bia')
    end
  end

  describe 'as recusas da instrução mantida nomeiam o contratado (o texto da Lia não muda)' do
    it 'PATCH com instruction: o texto do contratado, sem o Agente de Cotação' do
      patch "#{agents_url}/#{agente.id}", params: { agent: { instruction: 'x' } }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(texto_do_contratado)
      expect(response.parsed_body['error']).not_to include(I18n.t('autonomia.agents.instrucao_mantida'))
    end

    it 'o Construtor no contratado: o texto do contratado' do
      post "#{agents_url.delete_suffix('/agents')}/build_threads", params: { autonomia_agent_id: agente.id, message: 'muda o tom' },
                                                                   headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(texto_do_contratado)
    end

    it 'a Lia segue com o texto dela' do
      lia = Autonomia::Insurance::QuoteAgent::Builder.new(account: account, nome_agente: 'Lia', nome_corretora: 'Corretora Exemplo').call

      patch "#{agents_url}/#{lia.id}", params: { agent: { instruction: 'x' } }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.agents.instrucao_mantida'))
    end

    it 'o modo manual no model: o texto do contratado' do
      agente.mode = :manual

      expect(agente).not_to be_valid
      expect(agente.errors[:mode]).to eq([texto_do_contratado])
    end

    it 'o erro levantado pelo contratado é o dele, e ainda é uma InstrucaoMantida' do
      expect { agente.restore_instruction!(nil) }.to raise_error(Autonomia::Agents::Agent::InstrucaoDoContratado)
      expect(Autonomia::Agents::Agent::InstrucaoDoContratado.ancestors).to include(Autonomia::Agents::Agent::InstrucaoMantida)
    end
  end
end

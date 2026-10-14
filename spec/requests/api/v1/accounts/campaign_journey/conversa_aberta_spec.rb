require 'rails_helper'

# #1335: a conversa aberta funciona em toda conta com a flag nova, SEM a ponte de Modelos (whatsapp_templates_journey):
# contagem, preços e franquia saem do endpoint próprio. Sem a flag, 404. A IA é simulada: nenhum spec chama IA paga.
RSpec.describe 'Conversa aberta na campanha (#1335)', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'true', CAMPAIGN_IMPORT_ENABLED: 'true', CRM_KANBAN_ENABLED: 'true',
                      CRM_AI_ENABLED: 'true') { example.run }
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { journey_cloud_channel(account).inbox }
  let(:content) { "Nome,Celular,Link da oferta\nAna Souza,11987654321,https://x.com/1\nBia Lima,21987654321,https://x.com/2\n" }
  let(:audience) { saved_audience(account: account, user: user, content: content) }
  let(:headers) { { 'api_access_token' => user.access_token.token } }
  let(:base_path) { "/api/v1/accounts/#{account.id}/campaign_journey/conversa_aberta" }

  before do
    account.disable_features!(:whatsapp_templates_journey)
    account.enable_features!(:campaign_open_window_text)
  end

  def ana
    audience.campaign_import_rows.includes(:contact).map(&:contact).find { |contact| contact.name == 'Ana Souza' }
  end

  def contar(member: user, categoria: 'MARKETING', inbox_id: inbox.id)
    get base_path, params: { campaign_import_id: audience.id, inbox_id: inbox_id, categoria: categoria },
                   headers: { 'api_access_token' => member.access_token.token }
    response.parsed_body['payload']
  end

  describe 'GET contagem' do
    it 'conta quem falou nas últimas 24 h numa conta SEM a ponte de Modelos, com preço e franquia' do
      conversation = create(:conversation, account: account, inbox: inbox, contact: ana)
      create(:message, account: account, inbox: inbox, conversation: conversation, sender: ana, message_type: :incoming,
                       created_at: 2.hours.ago)

      payload = contar

      expect(account.reload.feature_enabled?(:whatsapp_templates_journey)).to be(false)
      expect(response).to have_http_status(:ok)
      expect(payload).to include('dentro' => 1, 'fora' => 1, 'fecham_logo' => 0)
      expect(payload['precos']).to eq('modelo' => { 'valor' => '0.3217', 'moeda' => 'BRL' },
                                      'escrita' => { 'valor' => '0.035', 'moeda' => 'BRL' })
      expect(payload['franquia']).to eq('limite' => 1000, 'usadas' => 0)
      expect(payload['campos'].pluck('chave')).to include('cliente.primeiro_nome', 'publico.Link_da_oferta')
    end

    it 'sem a flag da conta, 404' do
      account.disable_features!(:campaign_open_window_text)

      contar

      expect(response).to have_http_status(:not_found)
    end

    it 'agente sem campaign_manage não usa' do
      contar(member: agent)

      expect(response).to have_http_status(:unauthorized)
    end

    it 'caixa que não é do WhatsApp oficial é recusada' do
      contar(inbox_id: create(:inbox, account: account).id)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'público e caixa de outra conta não são achados' do
      other = create(:account)
      contar(inbox_id: create(:channel_whatsapp, account: other, sync_templates: false, validate_provider_config: false).inbox.id)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST escrever' do
    let(:client) { instance_double(Crm::Ai::ResponsesClient) }
    let(:enviado) { {} }

    before do
      Redis::Alfred.delete("conversa_aberta:escrever:#{account.id}:#{Time.zone.today.iso8601}")
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k' }))
      allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
      allow(client).to receive(:create) do |**kwargs|
        enviado.merge!(kwargs)
        opcao = { texto: 'Oi, {{cliente.primeiro_nome}}! As peças novas estão aqui: {{publico.Link_da_oferta}}. Quer ver?',
                  chaves_usadas: [], o_que_mudou: nil, categoria_prevista: nil, certeza_categoria: nil, motivo_categoria: nil }
        { text: { status: 'ok', pergunta: nil, sugestoes: [], problemas_encontrados: [], opcoes: [opcao] }.to_json }
      end
    end

    def escrever(body)
      post "#{base_path}/escrever", params: { campaign_import_id: audience.id, inbox_id: inbox.id }.merge(body),
                                    headers: headers, as: :json
      response.parsed_body['payload']
    end

    it 'chama o redator no canal de campanha, com as colunas do público como campos, e devolve as opções' do
      payload = escrever(objetivo: 'avisar da coleção nova', tom: 'curto', categoria: 'MARKETING')

      expect(response).to have_http_status(:ok)
      expect(payload['opcoes']).to eq([{ 'texto' => 'Oi, {{cliente.primeiro_nome}}! As peças novas estão aqui: ' \
                                                    '{{publico.Link_da_oferta}}. Quer ver?' }])
      entrada = JSON.parse(enviado[:input])
      expect(entrada['canal']).to eq('whatsapp_campanha')
      expect(entrada['pedido']).to eq('avisar da coleção nova')
      expect(entrada['tom']['escolha']).to eq('curto')
      expect(entrada['chaves']['permitidas'].pluck('chave')).to include('publico.Link_da_oferta', 'cliente.primeiro_nome')
      expect(entrada['contexto']).to eq('tipo_do_modelo' => 'divulgacao')
      expect(Crm::Ai::ResponsesClient).to have_received(:new).with(hash_including(feature: 'campanha_redacao'))
    end

    it 'melhorar: manda a base e a melhoria no vocabulário do redator' do
      escrever(base: 'Oi, {{cliente.primeiro_nome}}! Chegou a coleção nova. Quer ver?', melhoria: 'mais_curta')

      entrada = JSON.parse(enviado[:input])
      expect(entrada['base']).to start_with('Oi, {{cliente.primeiro_nome}}!')
      expect(entrada['pedido']).to eq('melhorias' => ['mais_curto'], 'observacao' => nil)
    end

    it 'mais simpática: tom simpático e uma observação no lugar de uma lista vazia' do
      escrever(base: 'Prezado {{cliente.nome}}, o relatório está disponível.', melhoria: 'mais_simpatica')

      entrada = JSON.parse(enviado[:input])
      expect(entrada['tom']['escolha']).to eq('simpatico')
      expect(entrada['pedido']).to eq('melhorias' => [], 'observacao' => 'deixar mais simpática e calorosa, sem mudar o assunto')
    end

    it 'passou do teto diário da conta: 429, sem chamar a IA' do
      stub_const('Api::V1::Accounts::CampaignJourney::ConversaAbertaController::LIMITE_DIARIO', 1)
      Redis::Alfred.delete("conversa_aberta:escrever:#{account.id}:#{Time.zone.today.iso8601}")

      escrever(objetivo: 'avisar da coleção nova')
      escrever(objetivo: 'de novo')

      expect(response).to have_http_status(:too_many_requests)
      expect(client).to have_received(:create).once
    end

    it 'IA fora do ar vira 503 com código, sem texto da pessoa no erro' do
      allow(client).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'boom')

      escrever(objetivo: 'avisar da coleção nova')

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body).to eq('error' => 'conversa_aberta.ia_indisponivel', 'code' => 'ia_indisponivel')
    end
  end
end

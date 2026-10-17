require 'rails_helper'

# #1702 — encaminhar mensagens pelo painel (GET/POST conversa_canal/encaminhamentos).
RSpec.describe 'Encaminhar mensagens', type: :request do
  let(:account) { create(:account) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:caixa) { create(:inbox, account: account, channel: create(:channel_api, account: account)) }
  let(:outra_caixa) { create(:inbox, account: account, channel: create(:channel_api, account: account)) }
  let(:ana) { create(:contact, account: account, name: 'Ana Souza', phone_number: '+5511911110000') }
  let(:bruno) { create(:contact, account: account, name: 'Bruno Lima', phone_number: '+5511922220000') }
  let(:origem) { create(:conversation, account: account, inbox: caixa, contact: ana) }
  let(:destino) { create(:conversation, account: account, inbox: caixa, contact: bruno) }
  let!(:mensagem) { create(:message, account: account, inbox: caixa, conversation: origem, message_type: :incoming, content: 'Olá') }

  before do
    account.enable_features!('conversa_cara_do_canal')
    account.save!
    create(:inbox_member, user: agente, inbox: caixa)
  end

  def encaminhar(destinos: [destino.display_id], message_ids: [mensagem.id], usuario: agente)
    post "/api/v1/accounts/#{account.id}/conversa_canal/encaminhamentos",
         params: { conversation_id: origem.display_id, message_ids: message_ids, conversation_ids: destinos },
         headers: usuario.create_new_auth_token, as: :json
  end

  def destinos(termo: nil, usuario: agente)
    get "/api/v1/accounts/#{account.id}/conversa_canal/encaminhamentos",
        params: { termo: termo }, headers: usuario.create_new_auth_token, as: :json
  end

  describe 'POST' do
    it 'cria a cópia no destino e responde o resultado por destino' do
      encaminhar

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to eq([{ 'conversation_id' => destino.display_id, 'ok' => true, 'erro' => nil }])
      copia = destino.messages.last
      expect(copia).to have_attributes(content: 'Olá', message_type: 'outgoing', sender: agente)
      expect(copia.content_attributes['forwarded']).to be(true)
    end

    it 'destino numa caixa que o atendente não vê: 401 e nada criado' do
      fora = create(:conversation, account: account, inbox: outra_caixa)

      encaminhar(destinos: [destino.display_id, fora.display_id])

      expect(response).to have_http_status(:unauthorized)
      expect(destino.messages.count).to eq(0)
    end

    it 'origem que o atendente não vê: 401' do
      outro = create(:user, account: account, role: :agent)

      encaminhar(usuario: outro)

      expect(response).to have_http_status(:unauthorized)
    end

    it 'mais de 5 destinos: 422 sem buscar nada' do
      encaminhar(destinos: (1..6).to_a)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('5')
    end

    it 'nota privada: 422 com a frase para a tela' do
      nota = create(:message, account: account, inbox: caixa, conversation: origem, message_type: :outgoing, private: true, content: 'interna')

      encaminhar(message_ids: [nota.id])

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('conversa_canal.encaminhar.nao_encaminhavel'))
    end

    describe 'só pessoa (encaminhamento automatizado é spam para o WhatsApp)' do
      def encaminhar_com_token(token)
        post "/api/v1/accounts/#{account.id}/conversa_canal/encaminhamentos",
             params: { conversation_id: origem.display_id, message_ids: [mensagem.id], conversation_ids: [destino.display_id] },
             headers: { api_access_token: token }, as: :json
      end

      it 'robô (AgentBot): 403 com a frase e nada criado' do
        robo = create(:agent_bot, account: account)
        create(:agent_bot_inbox, inbox: caixa, agent_bot: robo)

        encaminhar_com_token(robo.access_token.token)

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body['error']).to eq(I18n.t('conversa_canal.encaminhar.so_pessoa'))
        expect(destino.messages.count).to eq(0)
      end

      it 'token pessoal de uma pessoa (script, automação): 403' do
        encaminhar_com_token(agente.access_token.token)

        expect(response).to have_http_status(:forbidden)
        expect(destino.messages.count).to eq(0)
      end
    end

    it 'responde 404 com a chave da conta desligada' do
      account.disable_features!('conversa_cara_do_canal')
      account.save!

      encaminhar

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET' do
    it 'lista as conversas que o atendente vê, com a última linha' do
      destino
      create(:conversation, account: account, inbox: outra_caixa)

      destinos

      expect(response).to have_http_status(:ok)
      linhas = response.parsed_body['payload']
      expect(linhas.pluck('id')).to contain_exactly(origem.display_id, destino.display_id)
      expect(linhas.find { |linha| linha['id'] == origem.display_id }).to include('nome' => 'Ana Souza', 'ultima_linha' => 'Olá')
    end

    it 'filtra pelo nome ou telefone do contato' do
      destino

      destinos(termo: '92222')

      expect(response.parsed_body['payload'].pluck('id')).to eq([destino.display_id])
    end
  end
end

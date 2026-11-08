require 'rails_helper'

# Funções personalizadas, lote 4a (#1800): `conversation_view` lê as conversas que a pessoa alcança (caixa, time e
# funil) sem operar. A leitura passa por ConversationPolicy#view?; toda escrita segue em #show?, que só olha o trio
# conversation_*. Os cargos de hoje não mudam.
RSpec.describe 'Ler conversa sem operar com conversation_view', type: :request do
  let(:account) { create(:account) }
  let(:base) { "/api/v1/accounts/#{account.id}" }
  let(:dela) { create(:inbox, account: account) }
  let(:alheia) { create(:inbox, account: account) }
  let(:atendente) { create(:user, account: account, role: :agent) }
  let(:leitora) { pessoa_com(%w[conversation_view]) }
  let(:headers) { leitora.create_new_auth_token }
  let!(:conversa) { create(:conversation, account: account, inbox: dela, assignee: atendente, status: :open) }
  let!(:mensagem) { create(:message, account: account, inbox: dela, conversation: conversa, content: 'Quero uma cotação') }

  def pessoa_com(permissions, caixas: [dela])
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    caixas.each { |caixa| caixa.add_members([user.id]) }
    user
  end

  def ids_da_lista(user)
    get "#{base}/conversations", params: { status: 'all', assignee_type: 'all' }, headers: user.create_new_auth_token, as: :json
    response.parsed_body.dig('data', 'payload').pluck('id')
  end

  describe 'o que lê' do
    it 'vê a conversa de outra pessoa na lista e no filtro avançado' do
      expect(ids_da_lista(leitora)).to eq([conversa.display_id])

      post "#{base}/conversations/filter",
           params: { payload: [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['open'], query_operator: nil }] },
           headers: headers, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].pluck('id')).to eq([conversa.display_id])
    end

    it 'abre a conversa e lê mensagens, etiquetas, participantes e anexos' do
      path = "#{base}/conversations/#{conversa.display_id}"
      get path, headers: headers, as: :json
      expect(response).to have_http_status(:success)

      get "#{path}/messages", headers: headers, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].pluck('content')).to include('Quero uma cotação')

      %w[labels participants attachments].each do |parte|
        get "#{path}/#{parte}", headers: headers, as: :json
        expect(response).to have_http_status(:success), parte
      end
    end

    it 'não lê conversa de caixa que não é dela' do
      de_fora = create(:conversation, account: account, inbox: alheia)

      get "#{base}/conversations/#{de_fora.display_id}", headers: headers, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(ids_da_lista(leitora)).not_to include(de_fora.display_id)
    end
  end

  describe 'o que não faz' do
    # Toda rota de escrita sob /conversations/:id (scratchpad do lote: `rails routes` filtrado por conversa).
    let(:escritas) do
      c = "#{base}/conversations/#{conversa.display_id}"
      m = "#{c}/messages/#{mensagem.id}"
      [
        [:patch, c, { priority: 'urgent' }], [:put, c, { priority: 'urgent' }],
        [:delete, c, {}],
        [:post, "#{c}/mute", {}], [:post, "#{c}/unmute", {}],
        [:post, "#{c}/transcript", { email: 'fora@example.com' }],
        [:post, "#{c}/toggle_status", { status: 'resolved' }],
        [:post, "#{c}/toggle_priority", { priority: 'urgent' }],
        [:post, "#{c}/toggle_typing_status", { typing_status: 'on' }],
        [:post, "#{c}/update_last_seen", {}], [:post, "#{c}/unread", {}],
        [:post, "#{c}/custom_attributes", { custom_attributes: { plano: 'ouro' } }],
        [:post, "#{c}/destroy_custom_attributes", { custom_attribute: ['plano'] }],
        [:post, "#{c}/messages", { content: 'resposta' }],
        [:patch, m, { status: 'read' }], [:put, m, { status: 'read' }], [:delete, m, {}],
        [:post, "#{m}/retry", {}], [:post, "#{m}/translate", { target_language: 'en' }],
        [:post, "#{c}/participants", { user_ids: [leitora.id] }],
        [:patch, "#{c}/participants", { user_ids: [leitora.id] }], [:put, "#{c}/participants", { user_ids: [leitora.id] }],
        [:delete, "#{c}/participants", { user_ids: [atendente.id] }],
        [:patch, "#{c}/draft_messages", { draft_message: { message: 'x' } }],
        [:put, "#{c}/draft_messages", { draft_message: { message: 'x' } }], [:delete, "#{c}/draft_messages", {}],
        [:post, "#{c}/assignments", { assignee_id: leitora.id }],
        [:post, "#{c}/labels", { labels: ['vip'] }],
        [:patch, "#{c}/labels/alterar", { por: ['vip'] }],
        [:post, "#{c}/contact_info_request", {}],
        [:post, "#{c}/passar_para", { tipo: 'pessoa', id: leitora.id }],
        [:post, "#{c}/direct_uploads", { blob: { filename: 'a.png', byte_size: '1', checksum: 'abc', content_type: 'image/png' } }]
      ]
    end

    it 'recusa toda escrita na conversa, sem efeito' do
      escritas.each do |verbo, rota, params|
        public_send(verbo, rota, params: params, headers: headers, as: :json)

        expect(response).to have_http_status(:unauthorized), "#{verbo.upcase} #{rota.delete_prefix(base)}"
      end

      conversa.reload
      expect(conversa).to have_attributes(status: 'open', assignee_id: atendente.id, priority: nil, label_list: [], custom_attributes: {})
      expect(conversa.messages.pluck(:content)).to eq(['Quero uma cotação'])
      expect(conversa.conversation_participants).to be_empty
      expect(mensagem.reload.content).to eq('Quero uma cotação')
    end

    it 'não começa conversa nova' do
      contato = create(:contact, account: account)
      contact_inbox = create(:contact_inbox, contact: contato, inbox: dela)

      expect do
        post "#{base}/conversations", params: { contact_id: contato.id, inbox_id: dela.id, source_id: contact_inbox.source_id },
                                      headers: headers, as: :json
      end.not_to change(Conversation, :count)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'não cria o vínculo do contato com a caixa ao tentar começar conversa' do
      contato = create(:contact, account: account)

      expect do
        post "#{base}/conversations", params: { contact_id: contato.id, inbox_id: dela.id }, headers: headers, as: :json
      end.not_to change(ContactInbox, :count)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'não lê o rascunho de quem atende' do
      Redis::Alfred.set(format(Redis::Alfred::CONVERSATION_DRAFT_MESSAGE, id: conversa.id), 'proposta em preparo')

      get "#{base}/conversations/#{conversa.display_id}/draft_messages", headers: headers, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'não lê conversa de outra conta' do
      outra_conta = create(:account)
      de_outra = create(:conversation, account: outra_conta, inbox: create(:inbox, account: outra_conta))

      get "/api/v1/accounts/#{outra_conta.id}/conversations/#{de_outra.display_id}", headers: headers, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'não resolve em massa; quem opera, resolve' do
      resolver = lambda do |auth|
        perform_enqueued_jobs do
          post "#{base}/bulk_actions", params: { type: 'Conversation', ids: [conversa.display_id], fields: { status: 'resolved' } },
                                       headers: auth, as: :json
        end
      end
      leitura = headers
      operacao = pessoa_com(%w[conversation_manage]).create_new_auth_token

      resolver.call(leitura)
      expect(conversa.reload.status).to eq('open')

      resolver.call(operacao)
      expect(conversa.reload.status).to eq('resolved')
    end
  end

  describe 'com o trio junto' do
    let(:vendedora) { pessoa_com(%w[conversation_view conversation_participating_manage]) }

    it 'lê a conversa dos outros, mas só responde na dela' do
      minha = create(:conversation, account: account, inbox: dela, assignee: vendedora)
      auth = vendedora.create_new_auth_token

      expect(ids_da_lista(vendedora)).to contain_exactly(conversa.display_id, minha.display_id)

      get "#{base}/conversations/#{conversa.display_id}/messages", headers: auth, as: :json
      expect(response).to have_http_status(:success)

      post "#{base}/conversations/#{conversa.display_id}/messages", params: { content: 'oi' }, headers: auth, as: :json
      expect(response).to have_http_status(:unauthorized)

      post "#{base}/conversations/#{minha.display_id}/messages", params: { content: 'oi' }, headers: auth, as: :json
      expect(response).to have_http_status(:success)
    end

    # Subir o anexo segue a mesma regra de responder (#2147).
    it 'sobe anexo só na conversa que opera' do
      minha = create(:conversation, account: account, inbox: dela, assignee: vendedora)
      auth = vendedora.create_new_auth_token
      blob = { blob: { filename: 'a.png', byte_size: '1', checksum: 'abc', content_type: 'image/png' } }

      post "#{base}/conversations/#{conversa.display_id}/direct_uploads", params: blob, headers: auth, as: :json
      expect(response).to have_http_status(:unauthorized)

      post "#{base}/conversations/#{minha.display_id}/direct_uploads", params: blob, headers: auth, as: :json
      expect(response).to have_http_status(:success)
    end

    it 'começa conversa nova' do
      contato = create(:contact, account: account)
      contact_inbox = create(:contact_inbox, contact: contato, inbox: dela)

      post "#{base}/conversations", params: { contact_id: contato.id, inbox_id: dela.id, source_id: contact_inbox.source_id },
                                    headers: vendedora.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end
  end

  describe 'nada muda para quem já tem cargo' do
    it 'só as minhas: não vê nem abre a conversa dos outros' do
      so_minhas = pessoa_com(%w[conversation_participating_manage])

      expect(ids_da_lista(so_minhas)).to be_empty

      get "#{base}/conversations/#{conversa.display_id}", headers: so_minhas.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'todas da caixa: lê e responde' do
      gerente = pessoa_com(%w[conversation_manage])
      auth = gerente.create_new_auth_token

      expect(ids_da_lista(gerente)).to eq([conversa.display_id])

      post "#{base}/conversations/#{conversa.display_id}/messages", params: { content: 'oi' }, headers: auth, as: :json
      expect(response).to have_http_status(:success)
    end

    it 'cargo sem chave de conversa: lista vazia e conversa fechada, como antes' do
      so_crm = pessoa_com(%w[crm_view])

      expect(ids_da_lista(so_crm)).to be_empty

      get "#{base}/conversations/#{conversa.display_id}", headers: so_crm.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'atendente sem cargo: lê e responde na caixa dele' do
      sem_cargo = create(:user, account: account, role: :agent)
      dela.add_members([sem_cargo.id])

      expect(ids_da_lista(sem_cargo)).to eq([conversa.display_id])

      post "#{base}/conversations/#{conversa.display_id}/messages", params: { content: 'oi' },
                                                                    headers: sem_cargo.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end

    it 'administrador e atendente sem cargo veem exatamente as conversas de antes' do
      de_fora = create(:conversation, account: account, inbox: alheia)
      admin = create(:user, account: account, role: :administrator)
      sem_cargo = create(:user, account: account, role: :agent)
      dela.add_members([sem_cargo.id])

      expect(ids_da_lista(admin)).to contain_exactly(conversa.display_id, de_fora.display_id)
      expect(ids_da_lista(sem_cargo)).to eq([conversa.display_id])

      get "#{base}/conversations/#{de_fora.display_id}", headers: sem_cargo.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      post "#{base}/conversations/#{de_fora.display_id}/messages", params: { content: 'oi' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end
  end
end

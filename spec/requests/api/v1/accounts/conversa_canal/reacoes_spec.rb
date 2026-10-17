require 'rails_helper'

# #1702 — o atendente reage a uma mensagem do WhatsApp pelo painel (POST conversa_canal/reacoes).
RSpec.describe 'Reação do atendente', type: :request do
  let(:account) { create(:account) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:canal) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false).tap do |c|
      c.provider_config = { 'api_key' => 'chave-da-caixa', 'phone_number_id' => '123', 'business_account_id' => '777' }
      c.save!(validate: false)
    end
  end
  let(:caixa) { canal.inbox }
  let(:contato) { create(:contact, account: account, phone_number: '+5511937016094') }
  let(:contact_inbox) { create(:contact_inbox, inbox: caixa, contact: contato, source_id: '5511937016094') }
  let(:conversa) { create(:conversation, account: account, inbox: caixa, contact: contato, contact_inbox: contact_inbox) }
  let!(:mensagem) do
    create(:message, account: account, inbox: caixa, conversation: conversa, message_type: :incoming, content: 'Oi',
                     source_id: 'wamid.DOCLIENTE')
  end
  let(:url_da_meta) { 'https://graph.facebook.com/v24.0/123/messages' }

  before do
    account.enable_features!('conversa_cara_do_canal')
    account.save!
    create(:inbox_member, user: agente, inbox: caixa)
  end

  def reagir(emoji, usuario: agente, message_id: mensagem.id)
    post "/api/v1/accounts/#{account.id}/conversa_canal/reacoes",
         params: { conversation_id: conversa.display_id, message_id: message_id, emoji: emoji },
         headers: usuario.create_new_auth_token, as: :json
  end

  def resposta_da_meta(status: 200, body: { messages: [{ id: 'wamid.REACAO' }] })
    stub_request(:post, url_da_meta).to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  it 'manda a reação à Meta no formato da doc e grava com o atendente' do
    pedido = resposta_da_meta.with(body: hash_including('type' => 'reaction', 'to' => '5511937016094',
                                                        'reaction' => { 'message_id' => 'wamid.DOCLIENTE', 'emoji' => '👍' }))

    reagir('👍')

    expect(response).to have_http_status(:ok)
    expect(pedido).to have_been_requested
    gravada = mensagem.reload.content_attributes['reactions']
    expect(gravada).to contain_exactly(include('emoji' => '👍', 'sender_type' => 'User', 'sender_id' => agente.id))
    expect(response.parsed_body['reactions'].pluck('emoji')).to eq(['👍'])
  end

  it 'emoji vazio tira a reação da empresa' do
    resposta_da_meta
    mensagem.update!(content_attributes: { 'reactions' => [{ 'emoji' => '👍', 'sender_type' => 'User', 'sender_id' => agente.id }] })

    reagir('')

    expect(response).to have_http_status(:ok)
    expect(mensagem.reload.content_attributes).not_to have_key('reactions')
  end

  it 'recusa da Meta: 422 com o motivo e nada gravado' do
    resposta_da_meta(status: 400, body: { error: { message: 'Message not found' } })

    reagir('👍')

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('Message not found')
    expect(mensagem.reload.content_attributes).not_to have_key('reactions')
  end

  it 'fora da janela de 24 h: recusa sem chamar a Meta' do
    mensagem.update!(created_at: 2.days.ago)

    reagir('👍')

    expect(response).to have_http_status(:unprocessable_entity)
    expect(a_request(:post, url_da_meta)).not_to have_been_made
  end

  it 'mais de um emoji: recusa' do
    reagir('👍❤️')

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'atendente sem acesso à caixa não reage' do
    outro = create(:user, account: account, role: :agent)

    reagir('👍', usuario: outro)

    expect(response).to have_http_status(:unauthorized)
  end

  it 'responde 404 com a chave da conta desligada' do
    account.disable_features!('conversa_cara_do_canal')
    account.save!

    reagir('👍')

    expect(response).to have_http_status(:not_found)
  end

  it 'robô (token de AgentBot) não reage: 401 (decisão dos Agentes IA, 16/10)' do
    robo = create(:agent_bot, account: account)
    create(:agent_bot_inbox, agent_bot: robo, inbox: caixa)

    post "/api/v1/accounts/#{account.id}/conversa_canal/reacoes",
         params: { conversation_id: conversa.display_id, message_id: mensagem.id, emoji: '👍' },
         headers: { api_access_token: robo.access_token.token }, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(a_request(:post, url_da_meta)).not_to have_been_made
  end
end

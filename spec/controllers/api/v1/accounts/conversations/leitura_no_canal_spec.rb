require 'rails_helper'

# #1702 — abrir a conversa no painel (update_last_seen com read_receipt) marca a última recebida como lida no WhatsApp.
RSpec.describe 'Read receipt on the WhatsApp channel when the agent opens the conversation', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false).tap do |c|
      c.provider_config = { 'api_key' => 'chave', 'phone_number_id' => '123', 'business_account_id' => '777' }
      c.save!(validate: false)
    end
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:meta_url) { 'https://graph.facebook.com/v24.0/123/messages' }
  let(:job) { ConversaCanal::LeituraNoCanalJob }

  before do
    account.enable_features!('conversa_cara_do_canal')
    create(:inbox_member, user: agent, inbox: inbox)
    create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, source_id: 'wamid.LAST')
    stub_request(:post, meta_url).to_return(status: 200, body: { success: true }.to_json, headers: { 'Content-Type' => 'application/json' })
    Redis::Alfred.delete("conversa_canal:leitura:#{conversation.id}")
  end

  after { Redis::Alfred.delete("conversa_canal:leitura:#{conversation.id}") }

  def abrir(headers: { api_access_token: agent.access_token.token }, **params)
    post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/update_last_seen",
         headers: headers, params: params, as: :json
  end

  it 'atendente abrindo a conversa: enfileira e a Meta recebe a lida da última recebida' do
    perform_enqueued_jobs(only: job) { abrir(read_receipt: true) }

    expect(response).to have_http_status(:success)
    expect(WebMock).to have_requested(:post, meta_url).once.with(body: hash_including('status' => 'read', 'message_id' => 'wamid.LAST'))
  end

  it 'não chama a Meta dentro do request' do
    abrir(read_receipt: true)

    expect(job).to have_been_enqueued.with(conversation).on_queue('low')
    expect(WebMock).not_to have_requested(:post, meta_url)
  end

  it 'sem read_receipt (marcar como lida pela lista, sincronização) não enfileira' do
    abrir

    expect(response).to have_http_status(:success)
    expect(job).not_to have_been_enqueued
  end

  it 'robô (AgentBot) não marca: a IA marca a dela junto do digitando' do
    abrir(headers: { api_access_token: agent_bot.access_token.token }, read_receipt: true)

    expect(job).not_to have_been_enqueued
  end

  it 'chave conversa_cara_do_canal desligada não enfileira' do
    account.disable_features!('conversa_cara_do_canal')

    abrir(read_receipt: true)

    expect(response).to have_http_status(:success)
    expect(job).not_to have_been_enqueued
  end

  it 'conversa só com nota privada do atendente não enfileira' do
    Message.where(conversation: conversation).delete_all
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, private: true, content: 'nota')

    abrir(read_receipt: true)

    expect(job).not_to have_been_enqueued
  end

  it 'mensagem já marcada não enfileira de novo' do
    perform_enqueued_jobs(only: job) { abrir(read_receipt: true) }
    Redis::Alfred.delete("conversa_canal:leitura:#{conversation.id}")
    clear_enqueued_jobs

    abrir(read_receipt: true)

    expect(job).not_to have_been_enqueued
    expect(WebMock).to have_requested(:post, meta_url).once
  end

  it 'falha ao enfileirar não muda a resposta e vira log' do
    allow(job).to receive(:agendar).and_raise(Redis::CannotConnectError)
    allow(Rails.logger).to receive(:info)

    abrir(read_receipt: true)

    expect(response).to have_http_status(:success)
    expect(Rails.logger).to have_received(:info)
      .with("[conversa_canal][leitura] enqueue failed conversation=#{conversation.id} Redis::CannotConnectError")
  end
end

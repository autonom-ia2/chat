require 'rails_helper'

# chat#1709 (fase 3): reagir e editar pelo painel na caixa WAHA comum. O chat2you grava e manda ao webhook da caixa um
# evento próprio, que o conector customizado leva ao motor.
RSpec.describe 'WAHA message actions API', type: :request do
  let(:engine) { 'https://waha.example' }
  let(:channel) do
    create(:channel_api, webhook_url: "#{engine}/webhooks/chatwoot/abc", additional_attributes: { 'provider' => 'waha', 'session' => 's1' })
  end
  let(:account) { channel.account }
  let(:agent) { create(:user, account: account, role: :administrator) }
  let(:conversation) { create(:conversation, inbox: channel.inbox, account: account) }
  let(:actions) { %w[react edit] }
  let(:events) { [] }

  around { |example| with_modified_env(WAHA_RICH_NATIVE_ENGINES: "#{engine}/") { example.run } }

  before do
    allow(Waha::EngineCapabilities).to receive(:actions) { |url| url == "#{engine}/" ? actions : [] }
    # O renderer do chat#1740 (a edição só existe com ele); o texto renderizado é marcado para o teste.
    allow(Waha::RichNative::OutgoingHints).to receive(:renderer_ready?).and_return(true)
    allow(Waha::RichNative::OutgoingHints).to receive(:whatsapp_text) { |text, _message = nil| "WA[#{text}]" }
    allow(WebhookJob).to receive(:perform_later) { |_url, payload, kind, **| events << payload if kind == :api_inbox_webhook }
    # A reação e a edição vão pelo job próprio, que tenta de novo (rodada de correção, item 12).
    # O evento é montado na hora da entrega, do estado atual (revisão do estresse, C5): aqui, logo ao pedir.
    allow(Waha::RichNative::MessageActionDeliveryJob).to receive(:perform_later) do |id, event, _delivery|
      events << Waha::RichNative::MessageActionDeliveryJob.new.payload_for(Message.find(id), event).deep_symbolize_keys
    end
    account.enable_features!(Waha::RichNative::FLAG)
  end

  def message_url(message, action)
    "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message.id}/#{action}"
  end

  def ours(content = 'Até amanhã', **attrs)
    create(:message, { message_type: :outgoing, content: content, conversation: conversation, inbox: channel.inbox, account: account,
                       sender: agent }.merge(attrs)).tap { events.clear }
  end

  def react(message, emoji, user: agent)
    post message_url(message, 'reaction'), params: { emoji: emoji }, headers: user.create_new_auth_token, as: :json
  end

  def edit(message, content, user: agent)
    patch message_url(message, 'content'), params: { content: content }, headers: user.create_new_auth_token, as: :json
  end

  describe 'reaction' do
    let(:colleague) { create(:user, account: account, role: :agent) }

    before { create(:inbox_member, user: colleague, inbox: channel.inbox) }

    it 'stores ONE business reaction (any agent replaces it) and sends the event to the connector; empty removes it' do
      customer = create(:message, message_type: :incoming, content: 'oi', conversation: conversation, inbox: channel.inbox,
                                  account: account)
      events.clear

      react(customer, '👍')
      react(customer, '❤️', user: colleague)

      expect(response).to have_http_status(:ok)
      reactions = customer.reload.content_attributes['reactions']
      expect(reactions.map { |reaction| reaction.slice('emoji', 'sender_type', 'sender_id') })
        .to eq([{ 'emoji' => '❤️', 'sender_type' => 'User', 'sender_id' => colleague.id }])
      expect(events.last).to include(event: 'c2y_message_reaction', id: customer.id, c2y_reaction: { emoji: '❤️' })

      react(customer, '')
      expect(customer.reload.content_attributes).not_to have_key('reactions')
      expect(events.last[:c2y_reaction]).to eq(emoji: '')
    end

    it 'offers no action on an inbox without secret (the connector refuses unsigned c2y events)' do
      channel.update_column(:secret, nil) # rubocop:disable Rails/SkipsModelValidations
      customer = create(:message, message_type: :incoming, content: 'oi', conversation: conversation, inbox: channel.inbox,
                                  account: account)
      events.clear

      expect(Waha::RichNative::WahaInbox.message_actions_for(conversation.reload)).to eq([])
      react(customer, '👍')

      expect(response).to have_http_status(:forbidden)
      expect(customer.reload.content_attributes).not_to have_key('reactions')
      expect(events).to be_empty
    end

    it 'refuses more than one emoji, notes, activities and failed messages (no event, no resend)' do
      react(ours, '👍👍')
      expect(response).to have_http_status(:unprocessable_entity)

      react(ours('nota', private: true), '👍')
      expect(response).to have_http_status(:unprocessable_entity)

      failed = ours('falhou', status: :failed, content_attributes: { external_error: 'timeout' })
      react(failed, '👍')
      expect(response).to have_http_status(:unprocessable_entity)
      expect(failed.reload.content_attributes).not_to have_key('reactions')
      expect(events).to be_empty
    end

    # A mesma regra da reação pela pele (Whatsapp::EmojiDeReacao): letra, número e sinal do teclado não são emoji.
    it 'refuses ASCII in place of the emoji (422, nothing stored)' do
      message = ours
      %w[a 1 #].each do |ascii|
        react(message, ascii)
        expect(response).to have_http_status(:unprocessable_entity), ascii
      end
      expect(message.reload.content_attributes).not_to have_key('reactions')
      expect(events).to be_empty
    end

    # O pedido que nem sai não é sucesso calado: a nota "não chegou ao WhatsApp", na hora.
    it 'leaves the not-delivered note when the broadcast guard blocks the conversation' do
      message = ours
      allow(Autonomia::Channels::BroadcastGuard).to receive(:blocked_conversation?).and_return(true)

      react(message, '👍')

      expect(response).to have_http_status(:ok)
      expect(events).to be_empty
      expect(conversation.messages.where(private: true).pluck(:content))
        .to contain_exactly(I18n.t('waha.message_actions.reaction_not_delivered', locale: account.locale))
    end

    it 'leaves the not-delivered note when the inbox has no webhook address' do
      message = ours
      channel.update_column(:webhook_url, '') # rubocop:disable Rails/SkipsModelValidations

      Waha::RichNative::MessageActions.deliver(message.reload, Waha::RichNative::MessageActions::EDIT_EVENT)

      expect(events).to be_empty
      expect(conversation.messages.where(private: true).pluck(:content))
        .to contain_exactly(I18n.t('waha.message_actions.edit_not_delivered', locale: account.locale))
    end

    it 'refuses the view once notice (rodada de correção, item 10)' do
      notice = create(:message, message_type: :incoming, content: 'Você recebeu uma mensagem de visualização única.',
                                conversation: conversation, inbox: channel.inbox, account: account)
      notice.update_column(:content_attributes, { 'view_once_unavailable' => true }) # rubocop:disable Rails/SkipsModelValidations
      events.clear

      react(notice, '👍')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(notice.reload.content_attributes).not_to have_key('reactions')
      expect(events).to be_empty
    end

    it 'is forbidden without the flag or without the engine action' do
      message = ours
      account.disable_features!(Waha::RichNative::FLAG)
      react(message, '👍')
      expect(response).to have_http_status(:forbidden)

      account.enable_features!(Waha::RichNative::FLAG)
      allow(Waha::EngineCapabilities).to receive(:actions).and_return(['edit'])
      react(message, '👍')
      expect(response).to have_http_status(:forbidden)
      expect(events).to be_empty
    end
  end

  describe 'edit' do
    it 'replaces the text, keeps the previous one and sends the WhatsApp text to the connector' do
      message = ours('**Até** amanhã')

      edit(message, '**Até** depois')

      expect(response).to have_http_status(:ok)
      message.reload
      expect(message.content).to eq('**Até** depois')
      expect(message.content_attributes['edit_history'].sole)
        .to include('content' => '**Até** amanhã', 'sender_type' => 'User', 'sender_id' => agent.id)
      expect(message.content_attributes['edited_at']).to be_present
      expect(events.last).to include(event: 'c2y_message_edit', id: message.id, c2y_edit: { waha_text: 'WA[**Até** depois]' })
    end

    it 'refuses after the window, messages from the customer, rich, failed, blank and too long text' do
      old = travel_to(15.minutes.ago) { ours }
      customer = create(:message, message_type: :incoming, content: 'oi', conversation: conversation, inbox: channel.inbox,
                                  account: account)
      rich = ours('Qual?', content_attributes: { rich_message: { type: 'options', options: [{ id: 'a', title: 'A' }] } })
      failed = ours('falhou', status: :failed, content_attributes: { external_error: 'timeout' })
      too_long = 'x' * (Waha::RichNative::Edits::MAX_LENGTH + 1)

      [[old, 'novo'], [customer, 'novo'], [rich, 'novo'], [failed, 'novo'], [ours, '  '], [ours, too_long]].each do |message, content|
        edit(message, content)
        expect(response).to have_http_status(:unprocessable_entity), message.content
      end
      expect(response.parsed_body['error']).to include('14 minutos').or include('14 minutes')
      expect(events.select { |event| event[:event] == 'c2y_message_edit' }).to be_empty
    end

    it 'answers the same text without saving nor sending anything (revisão, risco 9)' do
      message = ours('Até amanhã')

      edit(message, 'Até amanhã')

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['content']).to eq('Até amanhã')
      expect(message.reload.content_attributes).not_to have_key('edit_history')
      expect(events).to be_empty
      expect(Waha::RichNative::MessageActions.edit!(message, user: agent, content: 'Até amanhã')).to eq(:unchanged)
    end

    it 'lets only the author edit; an administrator edits anyone, including the bot' do
      colleague = create(:user, account: account, role: :agent)
      create(:inbox_member, user: colleague, inbox: channel.inbox)
      bot_message = ours('Resposta da IA', sender: create(:agent_bot, account: account))

      edit(ours, 'novo', user: colleague)
      expect(response).to have_http_status(:forbidden)

      edit(ours('do colega', sender: colleague), 'do colega, corrigido', user: colleague)
      expect(response).to have_http_status(:ok)

      edit(bot_message, 'Resposta corrigida')
      expect(response).to have_http_status(:ok)
      expect(bot_message.reload.content).to eq('Resposta corrigida')
    end

    it 'is forbidden without the engine action' do
      allow(Waha::EngineCapabilities).to receive(:actions).and_return(['react'])
      edit(ours, 'novo')
      expect(response).to have_http_status(:forbidden)
    end
  end

  it 'exposes the actions in the conversation only with the flag, and edit only with the chat#1740 renderer' do
    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}", headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['whatsapp_api_message_actions']).to eq(%w[react edit])

    allow(Waha::RichNative::OutgoingHints).to receive(:renderer_ready?).and_return(false)
    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}", headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['whatsapp_api_message_actions']).to eq(%w[react])

    account.disable_features!(Waha::RichNative::FLAG)
    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}", headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['whatsapp_api_message_actions']).to eq([])
  end
end

require 'rails_helper'

# #1702: atualização só de marca da pele (reação, lida, prévia...) não vai ao robô nem ao webhook da caixa API (o
# conector WAHA reenvia a mensagem quando vê `external_error` num message_updated). Webhook da conta continua.
describe ConversaCanal::AtualizacaoDaPele do
  let(:account) { create(:account) }
  let(:agent_bot) { create(:agent_bot) }
  let(:canal) { create(:channel_api, account: account, webhook_url: 'https://conector.test/chatwoot') }
  let(:inbox) { canal.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:message) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                     content: 'oi', content_attributes: { 'external_error' => nil })
  end

  before { account.enable_features!('conversa_cara_do_canal') }

  def evento(mudancas)
    Events::Base.new('message.updated', Time.zone.now, message: message, previous_changes: mudancas)
  end

  def reacao
    { 'content_attributes' => [{ 'external_error' => nil },
                               { 'external_error' => nil, 'reactions' => [{ 'emoji' => '👍' }] }],
      'updated_at' => [1.minute.ago, Time.current] }
  end

  describe '.so_da_pele?' do
    it 'reconhece mudança só em chaves da pele' do
      expect(described_class.so_da_pele?(reacao)).to be(true)
    end

    it 'reconhece o aviso de visualização única resolvido (#1709)' do
      mudancas = { 'content_attributes' => [{ 'view_once_unavailable' => true },
                                            { 'view_once_unavailable' => true, 'c2y_hidden' => true, 'view_once_resolved_by' => 42 }] }

      expect(described_class.so_da_pele?(mudancas)).to be(true)
    end

    it 'não reconhece mudança de texto ou de outra chave' do
      expect(described_class.so_da_pele?(reacao.merge('content' => %w[oi olá]))).to be(false)
      expect(described_class.so_da_pele?('content_attributes' => [{}, { 'external_error' => 'falhou' }])).to be(false)
      expect(described_class.so_da_pele?('content_attributes' => [{}, {}])).to be(false)
      expect(described_class.so_da_pele?(nil)).to be(false)
      expect(described_class.so_da_pele?('content_attributes' => ['{"a":1}', '{"reactions":[]}'])).to be(false)
    end
  end

  describe 'robô (AgentBotListener)' do
    before { create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot) }

    it 'não manda ao robô a atualização só da pele' do
      expect(AgentBots::WebhookJob).not_to receive(:perform_later)

      AgentBotListener.instance.message_updated(evento(reacao))
    end

    it 'com a pele desligada, manda ao robô como na main' do
      account.disable_features!('conversa_cara_do_canal')
      expect(AgentBots::WebhookJob).to receive(:perform_later).once

      AgentBotListener.instance.message_updated(evento(reacao))
    end

    it 'manda ao robô a atualização de sempre' do
      expect(AgentBots::WebhookJob).to receive(:perform_later).once

      AgentBotListener.instance.message_updated(evento('content' => %w[oi olá]))
    end
  end

  describe 'webhooks (WebhookListener)' do
    it 'não manda ao webhook da caixa API, mas manda ao da conta' do
      webhook = create(:webhook, account: account, subscriptions: ['message_updated'], url: 'https://conta.test/hook')
      allow(WebhookJob).to receive(:perform_later)

      WebhookListener.instance.message_updated(evento(reacao))

      expect(WebhookJob).not_to have_received(:perform_later).with('https://conector.test/chatwoot', any_args)
      expect(WebhookJob).to have_received(:perform_later).with(webhook.url, anything, :account_webhook, any_args)
    end

    it 'com a pele desligada, manda ao webhook da caixa API como na main' do
      account.disable_features!('conversa_cara_do_canal')
      allow(WebhookJob).to receive(:perform_later)

      WebhookListener.instance.message_updated(evento(reacao))

      expect(WebhookJob).to have_received(:perform_later).with('https://conector.test/chatwoot', anything, :api_inbox_webhook, any_args)
    end

    it 'a atualização de sempre continua indo ao webhook da caixa API' do
      allow(WebhookJob).to receive(:perform_later)

      WebhookListener.instance.message_updated(evento('content' => %w[oi olá]))

      expect(WebhookJob).to have_received(:perform_later).with('https://conector.test/chatwoot', anything, :api_inbox_webhook, any_args)
    end
  end
end

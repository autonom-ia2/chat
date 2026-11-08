require 'rails_helper'

# #1702: atualização só de marca da pele (reação, lida, prévia...) não vai ao robô nem ao webhook da caixa API (o
# conector WAHA reenvia a mensagem quando vê `external_error` num message_updated). Webhook da conta continua.
describe ConversaCanal::AtualizacaoDaPele do
  let(:account) { create(:account) }
  let(:agent_bot) { create(:agent_bot) }
  let(:canal) do
    create(:channel_api, account: account, webhook_url: 'https://conector.test/chatwoot',
                         additional_attributes: { 'provider' => 'waha', 'session' => '5511888880000' })
  end
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

  # #2113: a reação do Instagram é gravada com a chave `conversa_instagram`, sem a pele do WhatsApp.
  describe 'robô na caixa do Instagram' do
    let(:conta_instagram) { create(:account) }
    let(:caixa_instagram) { create(:channel_instagram, account: conta_instagram).inbox }
    let(:conversa_instagram) { create(:conversation, account: conta_instagram, inbox: caixa_instagram) }
    let!(:mensagem_instagram) do
      create(:message, account: conta_instagram, inbox: caixa_instagram, conversation: conversa_instagram,
                       message_type: :outgoing, content: 'Proposta', source_id: 'mid.A')
    end

    def evento_instagram(mudancas)
      Events::Base.new('message.updated', Time.zone.now, message: mensagem_instagram, previous_changes: mudancas)
    end

    before do
      create(:agent_bot_inbox, inbox: caixa_instagram, agent_bot: agent_bot)
      conta_instagram.disable_features!('conversa_cara_do_canal')
    end

    it 'só com a conversa do Instagram ligada, a reação não vai ao robô' do
      conta_instagram.enable_features!('conversa_instagram')
      expect(AgentBots::WebhookJob).not_to receive(:perform_later)

      AgentBotListener.instance.message_updated(evento_instagram(reacao))
    end

    it 'sem a chave do Instagram, vai ao robô como na main' do
      conta_instagram.disable_features!('conversa_instagram')
      expect(AgentBots::WebhookJob).to receive(:perform_later).once

      AgentBotListener.instance.message_updated(evento_instagram(reacao))
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

    it 'caixa API de integração própria (sem WAHA) recebe a atualização da pele como na main' do
      canal.update!(additional_attributes: {})
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

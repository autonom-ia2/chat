require 'rails_helper'

# chat#1473: o agente pergunta antes de montar a mensagem se pode usar um formato naquela caixa. A resposta
# precisa bater com o que a trava faz com uma mensagem válida desse tipo: este spec amarra as duas regras.
describe 'RichMessages.delivery_mode' do # rubocop:disable RSpec/DescribeClass
  let(:mute_type) do
    Class.new do
      def self.text_version? = false
      def initialize(_payload); end
      def error_for(_body); end
      def whatsapp_cloud_payload(_body) = { type: 'spec_mute', spec_mute: {} }
      def fallback_text(_body) = ''
    end
  end
  let(:valid_rich_messages) do
    { 'link_button' => { type: 'link_button', label: 'Abrir', url: 'https://exemplo.com.br/x' }, 'spec_mute' => { type: 'spec_mute' } }
  end

  before { stub_const('RichMessages::Types::SpecMute', mute_type) }

  def cloud_channel
    create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end

  def dialog360_channel
    stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
    create(:channel_whatsapp, sync_templates: false)
  end

  def conversation_in(channel, window_open:)
    inbox = channel.inbox
    conversation = create(:conversation, inbox: inbox, account: inbox.account)
    create(:message, message_type: :incoming, content: 'oi', conversation: conversation, inbox: inbox, account: inbox.account) if window_open
    conversation
  end

  def valid_message(conversation, type)
    create(:message, message_type: :outgoing, content: 'Corpo', conversation: conversation, inbox: conversation.inbox,
                     account: conversation.account, content_attributes: { rich_message: valid_rich_messages.fetch(type) })
  end

  # [caixa, janela aberta, modo do link_button, modo do tipo sem versão em texto]
  channels = {
    'WhatsApp oficial, janela aberta' => [:cloud_channel, true, :native, :native],
    'WhatsApp oficial, janela fechada' => [:cloud_channel, false, :text, :refused],
    'WhatsApp 360dialog' => [:dialog360_channel, true, :text, :refused],
    'caixa API (WAHA)' => [-> { create(:channel_api) }, true, :text, :refused],
    'Telegram' => [-> { create(:channel_telegram) }, true, :text, :refused],
    'Instagram' => [-> { create(:channel_instagram) }, true, :text, :refused],
    'e-mail' => [-> { create(:channel_email) }, true, :refused, :refused],
    'chat do site' => [-> { create(:channel_widget) }, true, :refused, :refused]
  }

  channels.each do |title, (channel_source, window_open, link_mode, mute_mode)|
    { 'link_button' => link_mode, 'spec_mute' => mute_mode }.each do |type, mode|
      it "is #{mode} for #{type} in #{title}, and the guard agrees" do
        channel = channel_source.is_a?(Symbol) ? send(channel_source) : instance_exec(&channel_source)
        conversation = conversation_in(channel, window_open: window_open)
        message = valid_message(conversation, type)

        expect(RichMessages.delivery_mode(inbox: channel.inbox, type: type, conversation: conversation)).to eq(mode)
        expect(RichMessages.error_for(message).present?).to eq(mode == :refused)
      end
    end
  end

  it 'is refused for a type that does not exist' do
    expect(RichMessages.delivery_mode(inbox: cloud_channel.inbox, type: 'carousel')).to eq(:refused)
  end

  describe 'without the conversation' do
    it 'never answers native, and lets a type with a text version go as text' do
      expect(RichMessages.delivery_mode(inbox: cloud_channel.inbox, type: 'link_button')).to eq(:text)
    end

    it 'refuses a type without a text version on WhatsApp oficial, since the window is unknown' do
      expect(RichMessages.delivery_mode(inbox: cloud_channel.inbox, type: 'spec_mute')).to eq(:refused)
    end
  end

  def queries_during(&)
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] unless payload[:name] == 'SCHEMA' || payload[:cached] }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &)
    queries
  end

  describe 'cost' do
    it 'does not query anything without the conversation' do
      inbox = cloud_channel.inbox
      inbox.channel

      expect(queries_during { RichMessages.delivery_mode(inbox: inbox, type: 'link_button') }).to be_empty
    end

    it 'reads the window with a single query when the conversation comes' do
      conversation = conversation_in(cloud_channel, window_open: true)
      inbox = conversation.inbox
      inbox.channel

      expect(queries_during { RichMessages.delivery_mode(inbox: inbox, type: 'link_button', conversation: conversation) }.size).to eq(1)
    end
  end
end

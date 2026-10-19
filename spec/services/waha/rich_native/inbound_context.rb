# Caixa WAHA comum com o conector (o dono do token) criando a mensagem pela API, para os specs do recebimento
# (chat#1709, rodada 2). `from_connector` cria como o conector cria; `flag_on!` liga a flag da conta.
RSpec.shared_context 'with a waha inbox and its connector' do
  let(:channel) do
    create(:channel_api, webhook_url: 'https://waha.example/webhooks/chatwoot/abc',
                         additional_attributes: { 'provider' => 'waha', 'session' => 's1' })
  end
  let(:inbox) { channel.inbox }
  let(:account) { channel.account }
  let(:conversation) { create(:conversation, inbox: inbox, account: account) }
  let(:connector) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  before do
    account.update!(locale: 'pt_BR')
    channel.update!(additional_attributes: channel.additional_attributes.merge('account_token_owner_user_id' => connector.id))
  end

  after { Current.reset }

  def flag_on!
    account.enable_features!(Waha::RichNative::FLAG)
  end

  # options: message_type (:incoming), private, content, user, target_conversation e attachments ([{ io, filename,
  # content_type, file_type }]).
  def from_connector(attributes, **options)
    message_type = options.fetch(:message_type, :incoming)
    target_conversation = options.fetch(:target_conversation, conversation)
    Current.user = options.fetch(:user, connector)
    message = target_conversation.messages.new(
      message_type: message_type, private: options.fetch(:private, false), inbox: inbox, account: account,
      content: options.fetch(:content, 'texto do conector'),
      sender: message_type == :incoming ? target_conversation.contact : connector, content_attributes: attributes
    )
    Array(options[:attachments]).each { |file| build_attachment(message, file) }
    message.save!
    message.reload
  ensure
    Current.user = nil
  end

  def build_attachment(message, file)
    message.attachments.build(account_id: account.id, file_type: file.fetch(:file_type, :file),
                              file: { io: StringIO.new(file.fetch(:body, 'x')), filename: file.fetch(:filename),
                                      content_type: file.fetch(:content_type) })
  end
end

require 'rails_helper'

describe Instagram::Messenger::SendOnInstagramService do
  subject(:send_reply_service) { described_class.new(message: message) }

  before do
    stub_request(:post, /graph\.facebook\.com/)
    create(:message, message_type: :incoming, inbox: instagram_messenger_inbox, account: account, conversation: conversation)
  end

  let!(:account) { create(:account) }
  let!(:instagram_channel) { create(:channel_instagram_fb_page, account: account, instagram_id: 'chatwoot-app-user-id-1') }
  let!(:instagram_messenger_inbox) { create(:inbox, channel: instagram_channel, account: account, greeting_enabled: false) }
  let!(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: instagram_messenger_inbox) }
  let(:conversation) { create(:conversation, contact: contact, inbox: instagram_messenger_inbox, contact_inbox: contact_inbox) }
  let(:response) { double }
  let(:mock_response) do
    instance_double(
      HTTParty::Response,
      :success? => true,
      :body => { message_id: 'anyrandommessageid1234567890' }.to_json,
      :parsed_response => { 'message_id' => 'anyrandommessageid1234567890' }
    )
  end

  let(:error_body) do
    {
      'error' => {
        'message' => 'The Instagram account is restricted.',
        'type' => 'OAuthException',
        'code' => 400,
        'fbtrace_id' => 'anyrandomfbtraceid1234567890'
      }
    }
  end

  let(:error_response) do
    instance_double(
      HTTParty::Response,
      :success? => false,
      :body => error_body.to_json,
      :parsed_response => error_body
    )
  end

  let(:response_with_error) do
    instance_double(
      HTTParty::Response,
      :success? => true,
      :body => error_body.to_json,
      :parsed_response => error_body
    )
  end

  describe '#perform' do
    context 'with reply' do
      before do
        allow(Facebook::Messenger::Configuration::AppSecretProofCalculator).to receive(:call).and_return('app_secret_key', 'access_token')
        allow(HTTParty).to receive(:post).and_return(mock_response)
      end

      context 'without message_tag HUMAN_AGENT' do
        before do
          InstallationConfig.where(name: 'ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT').first_or_create(value: false)
        end

        it 'if message is sent from chatwoot and is outgoing' do
          message = create(:message, message_type: 'outgoing', inbox: instagram_messenger_inbox, account: account, conversation: conversation)

          response = described_class.new(message: message).perform
          expect(response['message_id']).to eq('anyrandommessageid1234567890')
        end

        it 'if message is sent from chatwoot and is outgoing with multiple attachments' do
          message = build(
            :message,
            content: nil,
            message_type: 'outgoing',
            inbox: instagram_messenger_inbox,
            account: account,
            conversation: conversation
          )
          avatar = message.attachments.new(account_id: message.account_id, file_type: :image)
          avatar.file.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
          sample = message.attachments.new(account_id: message.account_id, file_type: :image)
          sample.file.attach(io: Rails.root.join('spec/assets/sample.png').open, filename: 'sample.png', content_type: 'image/png')
          message.save!

          service = described_class.new(message: message)

          # Stub the send_message method on the service instance
          allow(service).to receive(:send_message)
          service.perform

          # Now you can set expectations on the stubbed method for each attachment
          expect(service).to have_received(:send_message).exactly(:twice)
        end

        it 'if message with attachment is sent from chatwoot and is outgoing' do
          message = build(:message, message_type: 'outgoing', inbox: instagram_messenger_inbox, account: account, conversation: conversation)
          attachment = message.attachments.new(account_id: message.account_id, file_type: :image)
          attachment.file.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
          message.save!
          response = described_class.new(message: message).perform

          expect(response['message_id']).to eq('anyrandommessageid1234567890')
        end

        it 'if message sent from chatwoot is failed' do
          message = create(:message, message_type: 'outgoing', inbox: instagram_messenger_inbox, account: account, conversation: conversation)

          allow(HTTParty).to receive(:post).and_return(response_with_error)
          described_class.new(message: message).perform
          expect(HTTParty).to have_received(:post)
          expect(message.reload.status).to eq('failed')
          expect(message.reload.external_error).to eq('400 - The Instagram account is restricted.')
        end
      end

      context 'when replying with a quote' do
        let(:quoted) do
          create(:message, message_type: 'incoming', inbox: instagram_messenger_inbox, account: account, conversation: conversation,
                           source_id: 'mid-da-citada')
        end

        it 'sends reply_to with the mid of the quoted message' do
          message = create(:message, message_type: 'outgoing', inbox: instagram_messenger_inbox, account: account,
                                     conversation: conversation, content_attributes: { in_reply_to: quoted.id })

          described_class.new(message: message).perform

          expect(HTTParty).to have_received(:post).with(
            anything, hash_including(body: hash_including(reply_to: { mid: 'mid-da-citada' }, message: { text: message.content }))
          )
        end

        it 'does not send reply_to when the quoted message has no mid' do
          quoted.update!(source_id: nil)
          message = create(:message, message_type: 'outgoing', inbox: instagram_messenger_inbox, account: account,
                                     conversation: conversation, content_attributes: { in_reply_to: quoted.id })

          described_class.new(message: message).perform

          expect(HTTParty).to have_received(:post).with(anything, hash_including(body: hash_excluding(:reply_to)))
        end

        it 'does not quote a message the contact unsent' do
          quoted.update!(content: 'deleted', deleted: true)
          message = create(:message, message_type: 'outgoing', inbox: instagram_messenger_inbox, account: account,
                                     conversation: conversation, content_attributes: { in_reply_to: quoted.id })

          described_class.new(message: message).perform

          expect(HTTParty).to have_received(:post).with(anything, hash_including(body: hash_excluding(:reply_to))).once
        end

        it 'resends once without the quote when Meta refuses the reply_to' do
          allow(HTTParty).to receive(:post).with(anything, hash_including(body: hash_including(:reply_to))).and_return(error_response)
          message = create(:message, message_type: 'outgoing', inbox: instagram_messenger_inbox, account: account,
                                     conversation: conversation, content_attributes: { in_reply_to: quoted.id })

          described_class.new(message: message).perform

          expect(HTTParty).to have_received(:post).twice
          expect(message.reload.status).not_to eq('failed')
        end
      end

      context 'with message_tag HUMAN_AGENT (#2259: only a person, only after 24 hours)' do
        let(:agent) { create(:user, account: account, role: :agent) }
        let(:conversation) do
          create(:conversation, account: account, contact: contact, inbox: instagram_messenger_inbox, contact_inbox: contact_inbox)
        end

        before do
          InstallationConfig.where(name: 'ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT').delete_all
          InstallationConfig.create!(name: 'ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT', value: true, locked: false)
          GlobalConfig.clear_cache
          conversation.messages.incoming.each { |incoming| incoming.update!(created_at: 30.hours.ago) }
          allow(HTTParty).to receive(:post).and_return(mock_response)
        end

        it 'tags a reply typed by a person of the team' do
          message = create(:message, message_type: 'outgoing', inbox: instagram_messenger_inbox, account: account,
                                     conversation: conversation, sender: agent)

          described_class.new(message: message).perform

          expect(HTTParty).to have_received(:post)
            .with(anything, hash_including(body: hash_including(messaging_type: 'MESSAGE_TAG', tag: 'HUMAN_AGENT')))
        end

        it 'does not tag a bot reply' do
          message = create(:message, message_type: 'outgoing', inbox: instagram_messenger_inbox, account: account, conversation: conversation,
                                     sender: create(:agent_bot, account: account))

          described_class.new(message: message).perform

          expect(HTTParty).not_to have_received(:post).with(anything, hash_including(body: hash_including(tag: 'HUMAN_AGENT')))
        end
      end
    end

    context 'when handling errors' do
      before do
        allow(Facebook::Messenger::Configuration::AppSecretProofCalculator).to receive(:call).and_return('app_secret_key', 'access_token')
      end

      it 'handles HTTP errors' do
        message = create(:message, message_type: 'outgoing', inbox: instagram_messenger_inbox, account: account, conversation: conversation)
        allow(HTTParty).to receive(:post).and_return(error_response)

        described_class.new(message: message).perform

        expect(message.reload.status).to eq('failed')
        expect(message.reload.external_error).to eq('400 - The Instagram account is restricted.')
      end

      it 'handles response errors' do
        message = create(:message, message_type: 'outgoing', inbox: instagram_messenger_inbox, account: account, conversation: conversation)

        error_response = instance_double(
          HTTParty::Response,
          success?: true,
          body: { 'error' => { 'message' => 'Invalid message format', 'code' => 100 } }.to_json,
          parsed_response: { 'error' => { 'message' => 'Invalid message format', 'code' => 100 } }
        )

        allow(HTTParty).to receive(:post).and_return(error_response)

        described_class.new(message: message).perform

        expect(message.reload.status).to eq('failed')
        expect(message.reload.external_error).to eq('100 - Invalid message format')
      end
    end
  end
end

require 'rails_helper'

describe Instagram::SendOnInstagramService do
  subject(:send_reply_service) { described_class.new(message: message) }

  let!(:account) { create(:account) }
  let!(:instagram_channel) { create(:channel_instagram, account: account, instagram_id: 'instagram-message-id-123') }
  let!(:instagram_inbox) { create(:inbox, channel: instagram_channel, account: account, greeting_enabled: false) }

  let!(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: instagram_inbox) }
  let(:conversation) { create(:conversation, contact: contact, inbox: instagram_inbox, contact_inbox: contact_inbox) }
  let(:response) { double }
  let(:mock_response) do
    instance_double(
      HTTParty::Response,
      :success? => true,
      :body => { message_id: 'random_message_id' }.to_json,
      :parsed_response => { 'message_id' => 'random_message_id' }
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
        allow(HTTParty).to receive(:post).and_return(mock_response)
      end

      context 'without message_tag HUMAN_AGENT' do
        before do
          InstallationConfig.where(name: 'ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT').first_or_create(value: false)
        end

        it 'if message is sent from chatwoot and is outgoing' do
          message = create(:message, message_type: 'outgoing', inbox: instagram_inbox, account: account, conversation: conversation)

          response = described_class.new(message: message).perform
          expect(response['message_id']).to eq('random_message_id')
        end

        it 'if message is sent from chatwoot and is outgoing with multiple attachments' do
          message = build(:message, content: nil, message_type: 'outgoing', inbox: instagram_inbox, account: account,
                                    conversation: conversation)
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
          message = build(:message, message_type: 'outgoing', inbox: instagram_inbox, account: account, conversation: conversation)
          attachment = message.attachments.new(account_id: message.account_id, file_type: :image)
          attachment.file.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
          message.save!
          response = described_class.new(message: message).perform

          expect(response['message_id']).to eq('random_message_id')
        end

        it 'if message sent from chatwoot is failed' do
          message = create(:message, message_type: 'outgoing', inbox: instagram_inbox, account: account, conversation: conversation)

          allow(HTTParty).to receive(:post).and_return(response_with_error)
          described_class.new(message: message).perform
          expect(HTTParty).to have_received(:post)
          expect(message.reload.status).to eq('failed')
          expect(message.reload.external_error).to eq('400 - The Instagram account is restricted.')
        end
      end

      context 'when replying with a quote' do
        let(:quoted) do
          create(:message, message_type: 'incoming', inbox: instagram_inbox, account: account, conversation: conversation,
                           source_id: 'mid-da-citada')
        end

        it 'sends reply_to with the mid of the quoted message' do
          message = create(:message, message_type: 'outgoing', inbox: instagram_inbox, account: account, conversation: conversation,
                                     content_attributes: { in_reply_to: quoted.id })

          described_class.new(message: message).perform

          expect(HTTParty).to have_received(:post).with(
            anything, hash_including(body: hash_including(reply_to: { mid: 'mid-da-citada' }, message: { text: message.content }))
          )
        end

        it 'quotes only the first part when the message has attachment and text' do
          message = build(:message, content: 'Segue a foto', message_type: 'outgoing', inbox: instagram_inbox, account: account,
                                    conversation: conversation, content_attributes: { in_reply_to: quoted.id })
          attachment = message.attachments.new(account_id: message.account_id, file_type: :image)
          attachment.file.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
          message.save!
          service = described_class.new(message: message)
          allow(service).to receive(:send_message)

          service.perform

          expect(service).to have_received(:send_message).twice
          expect(service).to have_received(:send_message)
            .with(hash_including(reply_to: { mid: 'mid-da-citada' }, message: hash_including(:attachment))).once
          expect(service).to have_received(:send_message)
            .with(hash_including(message: { text: 'Segue a foto' })).once
          expect(service).not_to have_received(:send_message).with(hash_including(reply_to: anything, message: { text: 'Segue a foto' }))
        end

        it 'does not send reply_to when the quoted message has no mid' do
          quoted.update!(source_id: nil)
          message = create(:message, message_type: 'outgoing', inbox: instagram_inbox, account: account, conversation: conversation,
                                     content_attributes: { in_reply_to: quoted.id })

          described_class.new(message: message).perform

          expect(HTTParty).to have_received(:post).with(anything, hash_including(body: hash_excluding(:reply_to)))
        end

        it 'does not quote a message the contact unsent' do
          quoted.update!(content: 'deleted', deleted: true)
          message = create(:message, message_type: 'outgoing', inbox: instagram_inbox, account: account, conversation: conversation,
                                     content_attributes: { in_reply_to: quoted.id })

          described_class.new(message: message).perform

          expect(HTTParty).to have_received(:post).once
          expect(HTTParty).to have_received(:post).with(anything, hash_including(body: hash_excluding(:reply_to)))
          expect(message.reload.status).not_to eq('failed')
        end

        it 'resends once without the quote when Meta refuses the reply_to' do
          allow(HTTParty).to receive(:post).with(anything, hash_including(body: hash_including(:reply_to))).and_return(error_response)
          message = create(:message, message_type: 'outgoing', inbox: instagram_inbox, account: account, conversation: conversation,
                                     content_attributes: { in_reply_to: quoted.id })

          described_class.new(message: message).perform

          expect(HTTParty).to have_received(:post).twice
          expect(HTTParty).to have_received(:post).with(anything, hash_including(body: hash_excluding(:reply_to))).once
          expect(message.reload.status).not_to eq('failed')
          expect(message.source_id).to eq('random_message_id')
        end

        it 'marks failed when the resend without the quote also fails' do
          allow(HTTParty).to receive(:post).and_return(error_response)
          message = create(:message, message_type: 'outgoing', inbox: instagram_inbox, account: account, conversation: conversation,
                                     content_attributes: { in_reply_to: quoted.id })

          described_class.new(message: message).perform

          expect(HTTParty).to have_received(:post).twice
          expect(message.reload.status).to eq('failed')
        end

        it 'does not resend when the token is invalid' do
          token_error = { 'error' => { 'message' => 'Access token has expired', 'code' => 190 } }
          allow(HTTParty).to receive(:post).and_return(
            instance_double(HTTParty::Response, success?: false, body: token_error.to_json, parsed_response: token_error)
          )
          message = create(:message, message_type: 'outgoing', inbox: instagram_inbox, account: account, conversation: conversation,
                                     content_attributes: { in_reply_to: quoted.id })

          described_class.new(message: message).perform

          expect(HTTParty).to have_received(:post).once
          expect(message.reload.status).to eq('failed')
        end
      end

      context 'with message_tag HUMAN_AGENT (#2259: only a person, only after 24 hours)' do
        let(:agent) { create(:user, account: account, role: :agent) }
        let(:conversation) { create(:conversation, account: account, contact: contact, inbox: instagram_inbox, contact_inbox: contact_inbox) }

        before do
          InstallationConfig.where(name: 'ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT').delete_all
          InstallationConfig.create!(name: 'ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT', value: true, locked: false)
          GlobalConfig.clear_cache
          travel_to(30.hours.ago) { create(:message, message_type: 'incoming', inbox: instagram_inbox, account: account, conversation: conversation) }
          allow(HTTParty).to receive(:post).and_return(mock_response)
        end

        it 'tags a reply typed by a person of the team' do
          message = create(:message, message_type: 'outgoing', inbox: instagram_inbox, account: account,
                                     conversation: conversation, sender: agent)

          described_class.new(message: message).perform

          expect(HTTParty).to have_received(:post)
            .with(anything, hash_including(body: hash_including(messaging_type: 'MESSAGE_TAG', tag: 'HUMAN_AGENT')))
        end

        it 'tags every part of a person reply with an attachment' do
          message = build(:message, content: 'segue', message_type: 'outgoing', inbox: instagram_inbox, account: account,
                                    conversation: conversation, sender: agent)
          attachment = message.attachments.new(account_id: message.account_id, file_type: :image)
          attachment.file.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
          message.save!

          described_class.new(message: message).perform

          tagged = hash_including(body: hash_including(messaging_type: 'MESSAGE_TAG', tag: 'HUMAN_AGENT'))
          expect(HTTParty).to have_received(:post).with(anything, tagged).twice
        end

        it 'does not tag a bot reply' do
          message = create(:message, message_type: 'outgoing', inbox: instagram_inbox, account: account, conversation: conversation,
                                     sender: create(:agent_bot, account: account))

          described_class.new(message: message).perform

          expect(HTTParty).not_to have_received(:post).with(anything, hash_including(body: hash_including(tag: 'HUMAN_AGENT')))
        end
      end

      context 'when handling errors' do
        it 'handles HTTP errors' do
          message = create(:message, message_type: 'outgoing', inbox: instagram_inbox, account: account, conversation: conversation)
          allow(HTTParty).to receive(:post).and_return(error_response)

          described_class.new(message: message).perform

          expect(message.reload.status).to eq('failed')
          expect(message.reload.external_error).to eq('400 - The Instagram account is restricted.')
        end

        it 'handles response errors' do
          message = create(:message, message_type: 'outgoing', inbox: instagram_inbox, account: account, conversation: conversation)

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

        it 'handles reauthorization errors if access token is expired' do
          message = create(:message, message_type: 'outgoing', inbox: instagram_inbox, account: account, conversation: conversation)

          error_response = instance_double(
            HTTParty::Response,
            success?: false,
            body: { 'error' => { 'message' => 'Access token has expired', 'code' => 190 } }.to_json,
            parsed_response: { 'error' => { 'message' => 'Access token has expired', 'code' => 190 } }
          )

          allow(HTTParty).to receive(:post).and_return(error_response)

          described_class.new(message: message).perform

          expect(message.reload.status).to eq('failed')
          expect(message.reload.external_error).to eq('190 - Access token has expired')
          expect(instagram_channel.reload).to be_reauthorization_required
        end
      end
    end
  end
end

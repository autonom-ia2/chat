require 'rails_helper'
require_relative '../rich_native_context'

# chat#1709 (fase 3): plano B do Híbrido com a flag `whatsapp_rich_native`: enquete nativa, citação no envio, foto
# como foto, apagar para todos e o voto de volta. web_transport.rb e echo_reconciler_extension.rb seguem intocados.
describe WhatsappHybrid::RichNative::Quote do
  include_context 'with a hybrid inbox for rich native'

  let(:poll) { { type: 'poll', options: [{ id: 'sim', title: 'Sim' }, { id: 'nao', title: 'Não' }] } }

  def customer_message(source_id: 'wamid.HBgNNTUxMTkzNzAxNjA5NBUCABIYFjNFQjBDVVNUT01FUgA=')
    create(:message, message_type: :incoming, content: 'oi', conversation: conversation, account: account, inbox: inbox,
                     sender: contact, source_id: source_id)
  end

  def reply_to(quoted, content: 'Respondendo')
    create(:message, message_type: :outgoing, content: content, conversation: conversation, account: account, inbox: inbox,
                     sender: create(:user, account: account), content_attributes: { in_reply_to: quoted.id })
  end

  describe 'quote (in_reply_to -> reply_to)' do
    it 'sends without reply_to while the flag is off, the same request as before' do
      quoted = customer_message

      send_by_web(reply_to(quoted))

      expect(client).to have_received(:send_text).with(session: 'hybrid-test', chat_id: '5511937016094@c.us', text: 'Respondendo',
                                                       id: '3EB0AAAA')
    end

    it 'sends the physical id inside the wamid of the quoted message with the flag' do
      flag_on!
      quoted = customer_message

      send_by_web(reply_to(quoted))

      expect(client).to have_received(:send_text).with(hash_including(reply_to: WhatsappHybrid::Wamid.message_id(quoted.source_id)))
    end

    it 'uses the raw source id of a message that only went through the engine' do
      flag_on!
      quoted = create(:message, message_type: :outgoing, content: 'antes', conversation: conversation, account: account, inbox: inbox,
                                source_id: '3EB0SENT')

      send_by_web(reply_to(quoted))

      expect(client).to have_received(:send_text).with(hash_including(reply_to: '3EB0SENT'))
    end
  end

  it 'sends a poll natively by sendPoll with the generated id' do
    flag_on!
    allow(client).to receive(:send_poll).and_return({ 'id' => 'true_5511937016094@c.us_3EB0AAAA' })
    message = outgoing(poll, content: 'Vem amanhã?')

    send_by_web(message)

    expect(client).to have_received(:send_poll).with(session: 'hybrid-test', chat_id: '5511937016094@c.us', id: '3EB0AAAA',
                                                     poll: { name: 'Vem amanhã?', options: %w[Sim Não], multipleAnswers: false })
    expect(message.reload.content_attributes['rich_message_sent_as']).to eq('native')
  end

  describe 'photo as photo (MediaAsMedia)' do
    def with_image(content_type, filename)
      message = create(:message, message_type: :outgoing, content: 'legenda', conversation: conversation, account: account,
                                 inbox: inbox, sender: create(:user, account: account))
      blob = ActiveStorage::Blob.create_and_upload!(io: Rails.root.join('spec/assets/booking_small.webp').open, filename: filename,
                                                    content_type: content_type, identify: false)
      message.attachments.create!(account_id: account.id, file_type: :image, file: blob)
      message.reload
    end

    before { allow(client).to receive(:send_media).and_return({}) }

    it 'keeps the request of before without the flag' do
      send_by_web(with_image('image/webp', 'foto.webp'))

      expect(client).to have_received(:send_media).with('sendImage',
                                                        hash_including(media: hash_including(file: hash_including(mimetype: 'image/webp'))))
    end

    it 'sends a GIF as a video with the flag' do
      flag_on!
      send_by_web(with_image('image/gif', 'anima.gif'))

      expect(client).to have_received(:send_media).with('sendVideo', anything)
    end

    it 'sends a JPEG variant of a webp with the flag' do
      flag_on!
      message = with_image('image/webp', 'foto.webp')
      allow(WhatsappHybrid::RichNative::MediaClient).to receive(:jpeg_variant_url).and_return('https://s3.example/foto.jpg')

      send_by_web(message)

      expect(client).to have_received(:send_media)
        .with('sendImage', hash_including(media: hash_including(file: { url: 'https://s3.example/foto.jpg', mimetype: 'image/jpeg',
                                                                        filename: 'foto.jpg' }, caption: 'legenda')))
    end

    it 'keeps the original file when the server cannot make the JPEG (no image library)' do
      flag_on!
      message = with_image('image/webp', 'foto.webp')
      allow(WhatsappHybrid::RichNative::MediaClient).to receive(:jpeg_variant_url).and_raise(LoadError)

      send_by_web(message)

      expect(client).to have_received(:send_media).with('sendImage',
                                                        hash_including(media: hash_including(file: hash_including(mimetype: 'image/webp'))))
    end
  end

  describe 'delete for everyone (RevokeOnDelete)' do
    def sent_by_web
      create(:message, message_type: :outgoing, content: 'oops', conversation: conversation, account: account, inbox: inbox,
                       source_id: '3EB0SENT', sender: create(:user, account: account))
    end

    def delete_in_panel(message)
      message.update!(content: 'apagada', content_attributes: { deleted: true })
    end

    it 'does nothing without the flag' do
      message = sent_by_web

      expect { delete_in_panel(message) }.not_to have_enqueued_job(WhatsappHybrid::RichNative::RevokeJob)
    end

    it 'asks the engine to revoke the physical id with the flag' do
      flag_on!
      message = sent_by_web
      allow(Waha::Client).to receive(:new).and_return(client)
      allow(client).to receive(:delete_message).and_return({})

      perform_enqueued_jobs(only: WhatsappHybrid::RichNative::RevokeJob) { delete_in_panel(message) }

      expect(client).to have_received(:delete_message).with(session: 'hybrid-test', chat_id: '5511937016094@c.us',
                                                            message_id: 'true_5511937016094@c.us_3EB0SENT')
    end

    it 'never revokes a customer message or a note' do
      flag_on!
      customer = customer_message
      note = create(:message, message_type: :outgoing, private: true, content: 'nota', conversation: conversation, account: account,
                              inbox: inbox, source_id: 'x')

      expect { [customer, note].each { |message| delete_in_panel(message) } }.not_to have_enqueued_job(WhatsappHybrid::RichNative::RevokeJob)
    end
  end

  describe 'the vote back (PollVoteJob)' do
    def native_poll
      flag_on!
      allow(client).to receive(:send_poll).and_return({})
      message = outgoing(poll, content: 'Vem amanhã?')
      send_by_web(message)
      message.reload
    end

    def vote(options, vote_id: 'V1', from_me: false)
      described = WhatsappHybrid::RichNative::PollVoteJob
      described.perform_now(connection.id, { 'poll_id' => 'true_5511937016094@c.us_3EB0AAAA', 'options' => options,
                                             'vote_id' => vote_id, 'from_me' => from_me })
    end

    it 'records the vote on the poll, once per vote id, as a hidden customer turn' do
      poll_message = native_poll

      2.times { vote(['Não']) }

      expect(conversation.messages.activity).to be_empty
      expect(conversation.messages.incoming.sole.content_attributes).to include('poll_vote_applied_to' => poll_message.id, 'c2y_hidden' => true)
      expect(poll_message.reload.content_attributes['poll_votes'].sole['options']).to eq(['Não'])
    end

    it 'records a removed vote and ignores votes from the company phone' do
      poll_message = native_poll
      vote(['Sim'], vote_id: 'V1')
      vote([], vote_id: 'V2')
      vote(['Sim'], vote_id: 'V3', from_me: true)

      expect(conversation.messages.incoming.pluck(:source_id)).to eq(%w[waha-poll-vote-V1])
      expect(conversation.messages.activity.sole.content_attributes).to include('c2y_hidden' => true)
      expect(poll_message.reload.content_attributes['poll_votes'].sole['options']).to eq([])
    end
  end
end

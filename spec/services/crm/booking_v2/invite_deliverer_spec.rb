require 'rails_helper'

# Entrega do convite na conversa (#1190, J1-A1/A12): mensagem de saída do próprio usuário com o link, texto
# literal, `sent_at` e conversa gravados; texto editado precisa ter o link, ser texto puro e caber em 1000.
RSpec.describe Crm::BookingV2::InviteDeliverer do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:world) { build_booking_world(account: account) }
  let(:conversation) { create(:conversation, account: account, contact: world.contact) }
  let(:invite) { create_booking_invite(world: world) }

  around { |example| with_modified_env('FRONTEND_URL' => 'https://app.example.com') { example.run } }

  def deliver(text: nil, to: conversation)
    described_class.new(invite: invite, user: world.host, conversation: to, text: text).perform
  end

  it 'creates an outgoing message from the user with the ready text and records sent_at and the conversation' do
    message = freeze_time { deliver }

    expect(message).to be_persisted
    expect(message).to have_attributes(conversation_id: conversation.id, sender: world.host, message_type: 'outgoing', private: false)
    expect(message.content).to eq("Oi, Marcos! Escolha o melhor horário para você: #{invite.url}")
    expect(message.content_attributes['crm_booking_invite_id']).to eq(invite.id)
    expect(invite.reload).to have_attributes(conversation_id: conversation.id, channel: 'conversation', state: 'sent')
    expect(invite.sent_at).to be_present
    expect(invite.metadata).to include('delivered_text' => message.content, 'delivered_by_id' => world.host.id)
  end

  it 'refuses with cannot_reply when the channel window is closed, and sends nothing' do
    channel = create(:channel_api, account: account, additional_attributes: { 'agent_reply_time_window' => '12' })
    closed = create(:conversation, account: account, inbox: channel.inbox, contact: world.contact)

    expect { deliver(to: closed) }.to raise_error(Crm::BookingV2::InviteError, 'cannot_reply')
    expect(closed.messages.count).to eq(0)
    expect(invite.reload.sent_at).to be_nil
  end

  it 'sends the edited text literally (Liquid is not evaluated) and stores it as the delivered text' do
    text = "Marcos, {{contact.name}} veja: #{invite.url}"

    message = deliver(text: text)

    expect(message.content).to eq(text)
    expect(invite.reload.metadata['delivered_text']).to eq(text)
    expect(Crm::BookingV2::InviteSerializer.new(invite).as_json[:text]).to eq(text)
  end

  it 'refuses edited text without the link, with HTML or longer than 1000 characters, and sends nothing' do
    long = "#{'a' * 990} #{invite.url}"
    ['Sem link nenhum', "<b>Oi</b> #{invite.url}", long].each do |text|
      expect { deliver(text: text) }.to raise_error(Crm::BookingV2::InviteError, 'invite_text_invalid')
    end
    expect(conversation.messages.count).to eq(0)
    expect(invite.reload.sent_at).to be_nil
  end

  it 'refuses a conversation of another contact and a canceled or expired invite' do
    stranger = create_booking_contact(account: account, name: 'Outra', phone: '+5511966665555')
    other = create(:conversation, account: account, contact: stranger)
    expect { deliver(to: other) }.to raise_error(Crm::BookingV2::InviteError, 'invite_invalid')

    invite.update!(expires_at: 1.minute.ago)
    expect { deliver }.to raise_error(Crm::BookingV2::InviteError, 'invite_invalid')
    invite.update!(expires_at: 1.day.from_now, canceled_at: Time.current)
    expect { deliver }.to raise_error(Crm::BookingV2::InviteError, 'invite_invalid')
    expect(Message.where(conversation_id: [conversation.id, other.id]).count).to eq(0)
  end
end

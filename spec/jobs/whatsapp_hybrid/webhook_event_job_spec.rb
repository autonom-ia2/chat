require 'rails_helper'

RSpec.describe WhatsappHybrid::WebhookEventJob do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let!(:admin) { create(:user, account: inbox.account, role: :administrator) }
  let(:connection) do
    WhatsappHybrid::Connection.create!(account: inbox.account, inbox: inbox, session_name: 'hybrid-test', status: 'connected',
                                       connected_phone: channel.phone_number.delete('^0-9'), risk_accepted_at: Time.current)
  end

  describe 'session.status' do
    it 'marks the connection down and warns the administrators once per drop' do
      described_class.perform_now(connection.id, 'session.status', { 'status' => 'FAILED' })
      described_class.perform_now(connection.id, 'session.status', { 'status' => 'STOPPED' })

      expect(connection.reload.status).to eq('disconnected')
      expect(connection.routable?).to be(false)
      avisos = Autonomia::Guide::Aviso.where(account: inbox.account, user: admin)
      expect(avisos.count).to eq(1)
      expect(avisos.first.texto).to include(inbox.name)
      expect(avisos.first.gravidade).to eq('urgente')
    end

    it 'clears the drop when the session works again, so the next drop warns again' do
      described_class.perform_now(connection.id, 'session.status', { 'status' => 'FAILED' })
      described_class.perform_now(connection.id, 'session.status', { 'status' => 'WORKING' })

      expect(connection.reload.status).to eq('connected')
      expect(connection.down_alerted_at).to be_nil
    end

    it 'keeps the WhatsApp limit sent with the status' do
      capping = { 'cappingStatus' => 'FIRST_WARNING', 'totalQuota' => 1000, 'usedQuota' => 640, 'cycleEnd' => 1_790_000_000 }

      described_class.perform_now(connection.id, 'session.status', { 'status' => 'WORKING', 'capping' => capping })

      expect(WhatsappHybrid::Capping.new(connection).status).to eq('FIRST_WARNING')
    end

    it 'does not warn when the connection was never in use' do
      connection.update!(risk_accepted_at: nil)

      described_class.perform_now(connection.id, 'session.status', { 'status' => 'FAILED' })

      expect(Autonomia::Guide::Aviso.count).to eq(0)
    end
  end

  describe 'message.ack' do
    let(:contact) { create(:contact, account: inbox.account, phone_number: '+5511937016094') }
    let(:conversation) { create(:conversation, inbox: inbox, contact: contact, account: inbox.account) }
    let(:message) { create(:message, message_type: :outgoing, conversation: conversation, account: inbox.account, inbox: inbox) }

    before { Redis::Alfred.setex(WhatsappHybrid::WebTransport.message_key(connection, '3EB0ACK'), message.id, 60) }

    it 'moves a WhatsApp API message to delivered and then read' do
      described_class.perform_now(connection.id, 'message.ack', { 'id' => 'true_5511937016094@c.us_3EB0ACK', 'ack' => 2 })
      expect(message.reload.status).to eq('delivered')

      described_class.perform_now(connection.id, 'message.ack', { 'id' => 'true_5511937016094@c.us_3EB0ACK', 'ack' => 3 })
      expect(message.reload.status).to eq('read')
    end

    it 'ignores acks of messages it does not know' do
      described_class.perform_now(connection.id, 'message.ack', { 'id' => 'true_x@c.us_OUTRO', 'ack' => 3 })

      expect(message.reload.status).to eq('sent')
    end
  end
end

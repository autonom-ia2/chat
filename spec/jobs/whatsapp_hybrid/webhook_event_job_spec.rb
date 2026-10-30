require 'rails_helper'

RSpec.describe WhatsappHybrid::WebhookEventJob do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:connection) do
    WhatsappHybrid::Connection.create!(account: inbox.account, inbox: inbox, session_name: 'hybrid-test', status: 'connected',
                                       connected_phone: channel.phone_number.delete('^0-9'), risk_accepted_at: Time.current)
  end

  describe 'session.status' do
    before do
      create(:user, account: inbox.account, role: :administrator)
      Redis::Alfred.delete(WhatsappHybrid::DownAlert.chave_da_queda(connection))
    end

    it 'marks the connection down at once and leaves the warning for after the grace period (#2112)' do
      expect do
        described_class.perform_now(connection.id, 'session.status', { 'status' => 'FAILED' })
        described_class.perform_now(connection.id, 'session.status', { 'status' => 'STOPPED' })
      end.to have_enqueued_job(WhatsappHybrid::DownAlertJob).exactly(:once)

      expect(connection.reload.status).to eq('disconnected')
      expect(connection.routable?).to be(false)
      expect(Autonomia::Guide::Aviso.count).to eq(0)
    end

    it 'clears the drop when the session works again, so the next drop warns again' do
      described_class.perform_now(connection.id, 'session.status', { 'status' => 'FAILED' })
      described_class.perform_now(connection.id, 'session.status', { 'status' => 'WORKING' })

      expect(connection.reload.status).to eq('connected')
      expect(connection.down_alerted_at).to be_nil
      expect(Redis::Alfred.exists?(WhatsappHybrid::DownAlert.chave_da_queda(connection))).to be(false)
    end

    it 'keeps the WhatsApp limit sent with the status' do
      capping = { 'cappingStatus' => 'FIRST_WARNING', 'totalQuota' => 1000, 'usedQuota' => 640, 'cycleEnd' => 1_790_000_000 }

      described_class.perform_now(connection.id, 'session.status', { 'status' => 'WORKING', 'capping' => capping })

      expect(WhatsappHybrid::Capping.new(connection).status).to eq('FIRST_WARNING')
    end

    it 'keeps the new-conversations limit sent with the status (chat#1486)' do
      timelock = WhatsappHybrid::Timelock.new(connection)
      Redis::Alfred.delete(timelock.key)
      ends_at = 6.hours.from_now.to_i
      reachout = { 'enforcementType' => 'RESTRICT_ALL_COMPANIONS', 'isActive' => true, 'timeEnforcementEnds' => ends_at }

      described_class.perform_now(connection.id, 'session.status', { 'status' => 'WORKING', 'timelock' => reachout })

      expect(timelock.payload).to eq(active: true, ends_at: ends_at)
      expect(connection.reload.status).to eq('connected')
    end

    it 'leaves the limit snapshot alone when the status brings none' do
      timelock = WhatsappHybrid::Timelock.new(connection)
      timelock.apply!('isActive' => true, 'timeEnforcementEnds' => 3.hours.from_now.to_i)

      described_class.perform_now(connection.id, 'session.status', { 'status' => 'WORKING' })

      expect(timelock.active?).to be(true)
    end

    it 'does not warn when the connection was never in use' do
      connection.update!(risk_accepted_at: nil)

      expect { described_class.perform_now(connection.id, 'session.status', { 'status' => 'FAILED' }) }
        .not_to have_enqueued_job(WhatsappHybrid::DownAlertJob)
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

    it 'keeps the ✓✓ on our own messages when the ack says fromMe=true (#2246)' do
      described_class.perform_now(connection.id, 'message.ack',
                                  { 'id' => 'true_5511937016094@c.us_3EB0ACK', 'ack' => 3, 'from_me' => true, 'aparelho' => '0' })

      expect(message.reload.status).to eq('read')
    end

    it 'sends the ack of a received message read on the phone to the phone reading, not to the ✓✓ (#2246)' do
      ack = { 'id' => '3EB0ACK', 'ack' => 3, 'from_me' => false, 'aparelho' => '0' }
      leitura = instance_double(WhatsappHybrid::LeituraNoCelular, aplicar: :andou)
      allow(WhatsappHybrid::LeituraNoCelular).to receive(:new).with(connection).and_return(leitura)

      expect { described_class.perform_now(connection.id, 'message.ack', ack) }.not_to have_enqueued_job(described_class)

      expect(leitura).to have_received(:aplicar).with(ack)
      expect(message.reload.status).to eq('sent')
    end

    context 'when the phone read arrives before the received message was indexed (#2246)' do
      let(:ack) { { 'id' => '3EB0IN', 'ack' => 3, 'from_me' => false, 'aparelho' => '0' } }

      before { inbox.account.enable_features!(ConversaCanal::VistaNoCelular::FLAG) }

      it 'tries again later, with a growing wait' do
        freeze_time do
          expect { described_class.perform_now(connection.id, 'message.ack', ack) }
            .to have_enqueued_job(described_class).with(connection.id, 'message.ack', ack.merge('tentativa' => 1)).at(5.seconds.from_now)
        end
      end

      it 'moves the agent seen time once the index arrives and the retry runs' do
        allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
        Redis::Alfred.delete(WhatsappHybrid::Config.inbox_flag_key(inbox.id))
        received = create(:message, message_type: :incoming, conversation: conversation, account: inbox.account, inbox: inbox,
                                    sender: contact, source_id: 'wamid.HBgNNTUxMTkzNzAxNjA5NBUCABIYFDJBNUQyRDhEQTA4OUJFNDJFNEQ1AA==')
        read = ack.merge('id' => '2A5D2D8DA089BE42E4D5')

        described_class.perform_now(connection.id, 'message.ack', read)
        expect(conversation.reload.unread_incoming_messages).to include(received)

        WhatsappHybrid::LeituraNoCelular.indexar(received)
        perform_enqueued_jobs(only: described_class)

        expect(conversation.reload.unread_incoming_messages).not_to include(received)
      ensure
        Redis::Alfred.delete(WhatsappHybrid::LeituraNoCelular.chave(inbox.id, '2A5D2D8DA089BE42E4D5'))
      end

      it 'gives up after the last try' do
        expect { described_class.perform_now(connection.id, 'message.ack', ack.merge('tentativa' => 3)) }
          .not_to have_enqueued_job(described_class)
      end
    end

    it 'ignores acks of messages it does not know' do
      described_class.perform_now(connection.id, 'message.ack', { 'id' => 'true_x@c.us_OUTRO', 'ack' => 3 })

      expect(message.reload.status).to eq('sent')
    end
  end
end

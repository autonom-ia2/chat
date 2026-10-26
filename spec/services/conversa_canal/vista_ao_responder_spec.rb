require 'rails_helper'

# Resposta nossa marca a conversa como vista até ela (#2202, PR 0): como no WhatsApp, se eu respondi, já li.
RSpec.describe ConversaCanal::VistaAoResponder do
  let(:account) { create(:account) }
  let(:ana) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :open) }
  let(:bot) { create(:agent_bot, account: account) }

  before do
    create(:inbox_member, inbox: inbox, user: ana)
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
  end

  after { Current.reset }

  def do_cliente(content = 'Oi, tudo bem?')
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                     sender: conversation.contact, content: content)
  end

  def nossa(sender: ana, **attrs)
    message = build(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                              content: 'Tudo, e você?', **attrs)
    message.sender = sender
    message.save!
    message
  end

  def nao_lidas
    conversation.reload.unread_incoming_messages.count
  end

  describe 'mensagem nossa e pública' do
    before { 2.times { do_cliente } }

    it 'resposta pelo painel zera a não lida', :aggregate_failures do
      Current.user = ana
      expect(nao_lidas).to eq(2)

      resposta = nossa

      expect(nao_lidas).to eq(0)
      expect(conversation.reload.agent_last_seen_at).to be_within(1.second).of(resposta.created_at)
    end

    it 'eco do celular (sem remetente) zera' do
      nossa(sender: nil, content_attributes: { 'external_echo' => true })

      expect(nao_lidas).to eq(0)
    end

    it 'robô zera' do
      nossa(sender: bot)

      expect(nao_lidas).to eq(0)
    end

    it 'modelo do WhatsApp mandado na conversa zera' do
      nossa(additional_attributes: { 'template_params' => { 'name' => 'boas_vindas' } })

      expect(nao_lidas).to eq(0)
    end
  end

  describe 'mensagem que não diz que alguém leu' do
    before { do_cliente }

    it 'nota privada não zera' do
      nossa(private: true)

      expect(nao_lidas).to eq(1)
    end

    it 'campanha não zera', :aggregate_failures do
      nossa(additional_attributes: { 'campaign_id' => 7 })
      nossa(additional_attributes: { 'whatsapp_api_campaign_id' => 8 })

      expect(nao_lidas).to eq(1)
    end

    it 'envio automático em nome de alguém (automação, follow-up) não zera', :aggregate_failures do
      nossa(content_attributes: { 'automation_rule_id' => 1 })
      nossa(content_attributes: { 'crm_follow_up_id' => 2 })

      expect(nao_lidas).to eq(1)
    end

    it 'mensagem importada do histórico não zera' do
      nossa(sender: nil, content_attributes: { 'external_echo' => true, 'history_import' => true })

      expect(nao_lidas).to eq(1)
    end
  end

  it 'mensagem do cliente depois da nossa volta a contar', :aggregate_failures do
    do_cliente
    nossa
    expect(nao_lidas).to eq(0)

    travel 1.second do
      do_cliente('E aí?')
    end

    expect(nao_lidas).to eq(1)
  end

  it 'nunca volta o "visto" para trás (eco atrasado de mensagem antiga)' do
    visto = 1.minute.from_now.change(usec: 0)
    conversation.update_columns(agent_last_seen_at: visto) # rubocop:disable Rails/SkipsModelValidations

    nossa(sender: nil, content_attributes: { 'external_echo' => true })

    expect(conversation.reload.agent_last_seen_at).to eq(visto)
  end

  describe 'evento para a tela' do
    before do
      do_cliente
      Current.user = ana
    end

    it 'sai o conversation.read com a conversa já vista, para a lista apagar a bolinha', :aggregate_failures do
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

      nossa

      expect(Rails.configuration.dispatcher).to have_received(:dispatch)
        .with(Events::Types::CONVERSATION_READ, anything, hash_including(conversation: conversation))
      expect(ActionCableBroadcastJob).to have_been_enqueued
        .with(array_including(ana.pubsub_token), Events::Types::CONVERSATION_READ, hash_including(id: conversation.display_id))
    end

    it 'o message.created da resposta já leva a não lida zerada' do
      resposta = nossa

      expect(ActionCableBroadcastJob).to have_been_enqueued
        .with(anything, Events::Types::MESSAGE_CREATED, hash_including(id: resposta.id, conversation: hash_including(unread_count: 0)))
    end

    it 'nota privada não manda o evento' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

      nossa(private: true)

      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
        .with(Events::Types::CONVERSATION_READ, anything, anything)
    end
  end

  it 'falha ao marcar não impede o envio', :aggregate_failures do
    do_cliente
    allow(described_class).to receive(:marcar!).and_raise(ActiveRecord::StatementInvalid, 'boom')
    allow(ChatwootExceptionTracker).to receive(:new).and_call_original

    resposta = nil
    expect { resposta = nossa }.to have_enqueued_job(SendReplyJob)

    expect(resposta).to be_persisted
    expect(ChatwootExceptionTracker).to have_received(:new).with(an_instance_of(ActiveRecord::StatementInvalid), account: account)
  end
end

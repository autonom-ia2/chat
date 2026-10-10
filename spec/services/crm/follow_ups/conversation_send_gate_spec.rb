require 'rails_helper'

RSpec.describe Crm::FollowUps::ConversationSendGate do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:inbox) { create_crm_whatsapp_api_inbox(account: account, members: [user]) }
  let(:contact) { account.contacts.create!(name: 'Lead', phone_number: '+5511987651111') }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: user) }
  let(:card) do
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    account.crm_cards.create!(pipeline: pipeline, stage: stage, inbox: inbox, contact: contact,
                              primary_conversation: conversation, title: 'Lead')
  end
  let(:now) { Time.current }

  def follow_up(title = 'Retomar')
    account.crm_follow_ups.create!(card: card, conversation: conversation, title: title, due_at: 1.minute.ago,
                                   timezone: 'UTC', automation_mode: :auto_send_message, created_by: user,
                                   metadata: { message_body: 'Oi' })
  end

  def automatic_message(follow_up_id, at: now)
    conversation.messages.create!(account_id: account.id, inbox_id: inbox.id, message_type: :outgoing, content: 'Toque',
                                  content_attributes: { crm_follow_up_id: follow_up_id }, created_at: at)
  end

  it 'envia quando a conversa está livre' do
    expect(described_class.new(follow_up, now: now).perform { :sent }).to eq(:sent)
  end

  it 'adia quando outro follow-up mandou mensagem automática há pouco' do
    automatic_message(follow_up('Outro pedido').id, at: now - 2.minutes)
    current = follow_up

    result = described_class.new(current, now: now).perform { raise 'não deveria enviar' }

    expect(result).to eq(:postponed)
    expect(current.reload.due_at).to be_within(1.second).of(now - 2.minutes + described_class::INTERVALO)
    expect(current).to be_pending
  end

  it 'não se bloqueia pela própria mensagem nem por envio antigo' do
    current = follow_up
    automatic_message(current.id, at: now - 1.minute)
    automatic_message(follow_up('Antigo').id, at: now - 1.hour)

    expect(described_class.new(current, now: now).perform { :sent }).to eq(:sent)
  end

  it 'adia quando outro envio da mesma conversa está em andamento' do
    current = follow_up
    lock = Redis::LockManager.new
    key = "crm:follow_up:envio_automatico:conversa:#{conversation.id}"
    lock.lock(key, described_class::TRAVA.to_i)

    result = described_class.new(current, now: now).perform { raise 'não deveria enviar' }

    expect(result).to eq(:postponed)
    expect(current.reload.due_at).to be_within(1.second).of(now + described_class::ESPERA_TRAVADA)
  ensure
    lock&.unlock(key)
  end

  it 'lembrete interno (a IA avisa a equipe) não espera a vez da conversa' do
    card.pipeline.update!(metadata: { ai: { auto_followup: { enabled: true, mode: 'ai_reminder' } } })
    current = follow_up
    current.update!(metadata: current.metadata.merge('source' => 'ai_followup'))
    processor = Crm::FollowUps::DueProcessor.new(now: now)

    expect(processor.send(:lembrete_interno?, current)).to be(true)
    card.pipeline.update!(metadata: { ai: { auto_followup: { enabled: true } } })
    expect(processor.send(:lembrete_interno?, current.reload)).to be(false)
  end
end

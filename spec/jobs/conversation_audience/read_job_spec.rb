require 'rails_helper'

# #2277: a reading search, wave by wave — the list fills up, the ceiling asks first, "Parar" is never overwritten,
# one search per account reads at a time, and the bell rings at the end.
RSpec.describe ConversationAudience::ReadJob do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:contacts) { create_list(:contact, 3, account: account) }
  let(:conversations) { contacts.map { |contact| create(:conversation, account: account, inbox: inbox, contact: contact) } }
  let(:search) { reading_search }

  def reading_search(status: 'queued', ceiling: 10)
    ConversationAudienceSearch.create!(
      account: account, user: user, request: 'quem cotou', period: '30d', status: status, ceiling_usd: ceiling, run_token: SecureRandom.hex(4),
      conversations_total: 3, plan: { 'rule' => 'Pediu cotação', 'sure' => 'a', 'likely' => 'b', 'near' => 'c', 'name' => 'Cotaram' }
    ).tap do |search|
      ConversationAudienceBatch.create!(search: search, number: 1, conversation_ids: conversations.first(2).map(&:id), chars: 100)
      ConversationAudienceBatch.create!(search: search, number: 2, conversation_ids: [conversations.last.id], chars: 100)
    end
  end

  def answer(*people)
    { text: { pessoas: people.map { |id, group| { conversa: id.to_s, grupo: group, motivo: 'Cotou', provas: [] } } }.to_json,
      usage: { 'input_tokens' => 1000, 'output_tokens' => 100 } }
  end

  before do
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-da-conta' })
    conversations.each { |conversation| create(:message, account: account, inbox: inbox, conversation: conversation, content: 'Cotação?') }
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    # Batches run in parallel threads: the answer depends on which conversations the call carries, not on the order.
    allow(client).to receive(:create) do |args|
      last = args[:input].include?("CONVERSA #{conversations.last.id} ")
      last ? answer([conversations.last.id, 'fora']) : answer([conversations.first.id, 'certeza'])
    end
  end

  after { ConversationAudience::Semaphore.leave(search) }

  it 'reads every batch, keeps who was found, counts the cost and rings the bell when done' do
    described_class.perform_now(search.id, search.run_token)
    expect(described_class).to have_been_enqueued.with(search.id, search.run_token)
    described_class.perform_now(search.id, search.run_token)

    search.reload
    expect(search).to have_attributes(status: 'done', conversations_read: 3, finished_at: be_present)
    expect(search.spent_usd).to be_positive
    expect(search.people.pluck(:contact_id, :group)).to contain_exactly([contacts.first.id, 'certeza'], [contacts.last.id, 'fora'])
    expect(search.batches.pluck(:status).uniq).to eq(['done'])
    expect(Notification.where(user: user, primary_actor: search, notification_type: 'conversation_audience_ready').count).to eq(1)
    expect(Crm::AiUsageEvent.where(account: account, feature: 'campaign_conversation_audience_read').count).to eq(2)
  end

  it 'writes, when found, who cannot receive, and rings only in the panel' do
    described_class.perform_now(search.id, search.run_token)
    described_class.perform_now(search.id, search.run_token)

    expect(search.people.pluck(:left_aside).uniq).to eq(['sem_contato'])
    expect(Notification::PushNotificationJob).not_to have_been_enqueued
  end

  it 'stops at the ceiling before paying for a wave that could pass it' do
    capped = reading_search(ceiling: 0)

    described_class.perform_now(capped.id, capped.run_token)

    expect(capped.reload.status).to eq('ceiling')
    expect(client).not_to have_received(:create)
    ConversationAudience::Semaphore.leave(capped)
  end

  it 'does not overwrite a "Parar" clicked during the wave, nor ring the bell' do
    wave = instance_double(ConversationAudience::Wave)
    allow(ConversationAudience::Wave).to receive(:new).and_return(wave)
    allow(wave).to receive(:run) do
      search.update!(status: 'stopped')
      ConversationAudience::Wave::DONE
    end

    described_class.perform_now(search.id, search.run_token)

    expect(search.reload.status).to eq('stopped')
    expect(Notification.where(primary_actor: search)).to be_empty
  end

  it 'waits in line while another search of the account reads' do
    other = reading_search(status: 'reading')
    expect(ConversationAudience::Semaphore.enter(other)).to be(true)

    described_class.perform_now(search.id, search.run_token)

    expect(search.reload.status).to eq('queued')
    expect(client).not_to have_received(:create)
    ConversationAudience::Semaphore.leave(other)
  end

  it 'fails when the AI refuses the key, with what was read so far kept' do
    allow(client).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error.new('invalid key', status: 401))

    described_class.perform_now(search.id, search.run_token)

    expect(search.reload).to have_attributes(status: 'failed', error: 'ai_error')
    expect(search.batches.pending.count).to eq(2)
  end

  it 'stops without calling the AI when the person left the account while the search waited' do
    AccountUser.find_by(account: account, user: user).destroy!

    described_class.perform_now(search.id, search.run_token)

    expect(search.reload).to have_attributes(status: 'failed', error: 'no_access')
    expect(client).not_to have_received(:create)
    expect(Notification.where(primary_actor: search)).to be_empty
  end

  context 'with a role limited to one inbox' do
    let(:user) do
      create(:user, account: account, role: :agent).tap do |agent|
        role = create(:custom_role, account: account, permissions: %w[campaign_manage conversation_view])
        agent.account_users.find_by(account: account).update!(custom_role: role)
        create(:inbox_member, user: agent, inbox: inbox)
      end
    end

    it 'stops without calling the AI when the role lost conversation_view' do
      user.account_users.find_by(account: account).custom_role.update!(permissions: %w[campaign_manage])

      described_class.perform_now(search.id, search.run_token)

      expect(search.reload).to have_attributes(status: 'failed', error: 'no_access')
      expect(client).not_to have_received(:create)
    end

    it 'never sends the AI a conversation of an inbox the person lost between the plan and the reading' do
      search
      InboxMember.where(user: user, inbox: inbox).destroy_all

      described_class.perform_now(search.id, search.run_token)

      expect(client).not_to have_received(:create)
      expect(search.reload.people).to be_empty
    end
  end

  it 'ends a job of an older chain without reading, requeueing or giving the slot back' do
    stale = search.run_token
    search.update!(run_token: 'nova-cadeia')
    expect(ConversationAudience::Semaphore.enter(search)).to be(true)

    described_class.perform_now(search.id, stale)

    expect(client).not_to have_received(:create)
    expect(described_class).not_to have_been_enqueued
    expect(ConversationAudience::Semaphore.enter(reading_search)).to be(false)
  end

  it 'lets only the current chain end the search after a "Parar" and "Continuar" during a wave' do
    wave = instance_double(ConversationAudience::Wave)
    allow(ConversationAudience::Wave).to receive(:new).and_return(wave)
    allow(wave).to receive(:run) do
      ConversationAudienceSearch.where(id: search.id).update_all(status: 'queued', run_token: 'retomada') # rubocop:disable Rails/SkipsModelValidations
      ConversationAudience::Wave::DONE
    end

    described_class.perform_now(search.id, search.run_token)

    expect(search.reload).to have_attributes(status: 'queued', run_token: 'retomada')
    expect(Notification.where(primary_actor: search)).to be_empty
  end

  it 'reads a batch again after a pause when the AI was out, and stops as failed after the last try' do
    allow(client).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error.new('busy', status: 429))

    described_class.perform_now(search.id, search.run_token)

    expect(search.reload.status).to eq('reading')
    expect(search.batches.pluck(:attempts)).to eq([1, 1])
    expect(described_class).to have_been_enqueued.with(search.id, search.run_token)
                                                 .at(a_value_within(5.seconds).of(described_class::RETRY_WAIT.from_now))

    2.times { described_class.perform_now(search.id, search.run_token) }

    expect(search.reload).to have_attributes(status: 'failed', error: 'ai_error')
    expect(search.batches.pending.count).to eq(2)
  end

  it 'skips a batch the AI cannot answer after the last try, and reads the rest to the end' do
    allow(client).to receive(:create) do |args|
      last = args[:input].include?("CONVERSA #{conversations.last.id} ")
      last ? answer([conversations.last.id, 'certeza']) : { text: 'não é json', usage: {} }
    end

    4.times { described_class.perform_now(search.id, search.run_token) }

    expect(search.reload).to have_attributes(status: 'done', conversations_read: 1)
    expect(search.batches.order(:number).pluck(:status)).to eq(%w[skipped done])
    expect(search.people.pluck(:conversation_id)).to eq([conversations.last.id])
    expect(ConversationAudience::Payload.new(search).to_h[:skipped]).to eq(2)
  end
end

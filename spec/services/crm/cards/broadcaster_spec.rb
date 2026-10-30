require 'rails_helper'

RSpec.describe Crm::Cards::Broadcaster do
  let(:crm_card_updated_event) { Events::Types::CRM_CARD_UPDATED }

  around do |example|
    previous_value = ENV.fetch('CRM_KANBAN_ENABLED', nil)
    ENV['CRM_KANBAN_ENABLED'] = 'true'
    example.run
  ensure
    if previous_value.nil?
      ENV.delete('CRM_KANBAN_ENABLED')
    else
      ENV['CRM_KANBAN_ENABLED'] = previous_value
    end
  end

  it 'broadcasts inbox cards only to administrators and inbox members' do
    account, admin = create_account_and_user
    member, = create_crm_agent(account: account)
    outsider, = create_crm_agent(account: account)
    inbox = create_crm_inbox(account: account, members: [member])
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, inbox: inbox, title: 'Lead visível')

    broadcast_calls = capture_broadcast_calls

    described_class.broadcast(card, crm_card_updated_event)

    expect(broadcast_calls.pluck(:tokens).flatten).to contain_exactly(admin.pubsub_token, member.pubsub_token)
    expect(broadcast_calls.pluck(:tokens).flatten).not_to include(outsider.pubsub_token)
    broadcast_calls.each do |call|
      expect(call[:tokens].size).to eq(1)
      expect(call[:event_name]).to eq(crm_card_updated_event)
      expect(call[:payload][:account_id]).to eq(account.id)
      expect(call[:payload][:id]).to eq(card.id)
      expect(call[:payload][:title]).to eq('Lead visível')
    end
  end

  it 'keeps assigned-only inbox events restricted to the assigned users and administrators' do
    account, admin = create_account_and_user
    owner, = create_crm_agent(account: account)
    inbox_member, = create_crm_agent(account: account)
    inbox = create_crm_inbox(account: account, members: [owner, inbox_member])
    account.crm_inbox_settings.create!(inbox: inbox, visibility_mode: :assigned_only)
    contact = account.contacts.create!(name: 'Lead privado', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: owner)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      inbox: inbox,
      owner: owner,
      primary_conversation: conversation,
      title: 'Lead privado'
    )

    broadcast_calls = capture_broadcast_calls

    described_class.broadcast(card, crm_card_updated_event)

    expect(broadcast_calls.pluck(:tokens).flatten).to contain_exactly(admin.pubsub_token, owner.pubsub_token)
    expect(broadcast_calls.pluck(:tokens).flatten).not_to include(inbox_member.pubsub_token)
    broadcast_calls.each do |call|
      expect(call[:event_name]).to eq(crm_card_updated_event)
      expect(call[:payload][:conversation][:display_id]).to eq(conversation.display_id)
    end
  end

  it 'does not broadcast assigned-only cards to assignees of secondary linked conversations' do
    account, admin = create_account_and_user
    owner, = create_crm_agent(account: account)
    secondary_assignee, = create_crm_agent(account: account)
    inbox = create_crm_inbox(account: account, members: [owner, secondary_assignee])
    account.crm_inbox_settings.create!(inbox: inbox, visibility_mode: :assigned_only)
    primary_contact = account.contacts.create!(name: 'Lead primário', phone_number: '+5511987654321')
    secondary_contact = account.contacts.create!(name: 'Lead secundário', phone_number: '+5511987654322')
    primary_conversation = create_crm_conversation(account: account, inbox: inbox, contact: primary_contact, assignee: owner)
    secondary_conversation = create_crm_conversation(
      account: account,
      inbox: inbox,
      contact: secondary_contact,
      assignee: secondary_assignee
    )
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      inbox: inbox,
      owner: owner,
      primary_conversation: primary_conversation,
      title: 'Lead privado'
    )
    account.crm_card_conversations.create!(card: card, conversation: secondary_conversation, linked_by: admin)

    broadcast_calls = capture_broadcast_calls

    described_class.broadcast(card, crm_card_updated_event)

    tokens = broadcast_calls.pluck(:tokens).flatten
    expect(tokens).to contain_exactly(admin.pubsub_token, owner.pubsub_token)
    expect(tokens).not_to include(secondary_assignee.pubsub_token)
  end

  # Lista nova (#2283): o tempo real usa o mesmo PayloadBuilder; quem não vê a conversa não recebe quem a atende nem o
  # retorno ligado a ela.
  it 'does not send the hidden conversation assignee nor its follow-up id in real time' do
    account, admin = create_account_and_user
    admin.update!(name: 'Gestora Ana')
    member, = create_crm_agent(account: account)
    inbox = create_crm_inbox(account: account, members: [member])
    hidden_inbox = create_crm_inbox(account: account, name: 'Caixa da gestão')
    contact = account.contacts.create!(name: 'Lead', phone_number: '+5511987654323')
    hidden = create_crm_conversation(account: account, inbox: hidden_inbox, contact: contact, assignee: admin)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, inbox: inbox, primary_conversation: hidden, title: 'Lead')
    follow_up = account.crm_follow_ups.create!(card: card, conversation: hidden, created_by: admin, title: 'Retorno oculto',
                                               due_at: 1.day.ago, timezone: 'America/Sao_Paulo', status: :overdue)

    broadcast_calls = capture_broadcast_calls
    described_class.broadcast(card, crm_card_updated_event)
    payloads = broadcast_calls.to_h { |call| [call[:tokens].first, call[:payload]] }

    expect(payloads[member.pubsub_token]).to include(conversation_id: nil, current_responsible: nil, next_follow_up_id: nil)
    expect(payloads[member.pubsub_token]).not_to have_key(:responsible)
    expect(payloads[member.pubsub_token].to_json).not_to include('Gestora Ana')
    expect(payloads[admin.pubsub_token]).to include(conversation_id: hidden.id, next_follow_up_id: follow_up.id)
    expect(payloads[admin.pubsub_token][:current_responsible]).to include(type: 'agent', name: 'Gestora Ana')
  end

  it 'does not broadcast when CRM Kanban is disabled' do
    ENV['CRM_KANBAN_ENABLED'] = 'false'
    account, admin = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Sem evento')

    allow(ActionCableBroadcastJob).to receive(:perform_later)

    described_class.broadcast(card, crm_card_updated_event)

    expect(ActionCableBroadcastJob).not_to have_received(:perform_later)
  end

  it 'does not broadcast inbox cards to owners without inbox access' do
    account, admin = create_account_and_user
    owner, = create_crm_agent(account: account)
    hidden_inbox = create_crm_inbox(account: account)
    account.crm_inbox_settings.create!(inbox: hidden_inbox, visibility_mode: :assigned_only)
    contact = account.contacts.create!(name: 'Lead oculto', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: hidden_inbox, contact: contact)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      inbox: hidden_inbox,
      owner: owner,
      primary_conversation: conversation,
      title: 'Card sem acesso'
    )

    broadcast_calls = capture_broadcast_calls

    described_class.broadcast(card, crm_card_updated_event)

    tokens = broadcast_calls.pluck(:tokens).flatten
    expect(tokens).to contain_exactly(admin.pubsub_token)
    expect(tokens).not_to include(owner.pubsub_token)
  end

  def capture_broadcast_calls
    [].tap do |calls|
      allow(ActionCableBroadcastJob).to receive(:perform_later) do |tokens, event_name, payload|
        calls << { tokens: tokens, event_name: event_name, payload: payload }
      end
    end
  end
end

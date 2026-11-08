require 'rails_helper'

RSpec.describe Crm::Conversations::CardSyncer do
  around do |example|
    previous_value = ENV.fetch('CRM_KANBAN_ENABLED', nil)
    previous_dedup_window = ENV.fetch('CRM_AUTO_CREATE_DEDUP_WINDOW_DAYS', nil)
    ENV['CRM_KANBAN_ENABLED'] = 'true'
    ENV.delete('CRM_AUTO_CREATE_DEDUP_WINDOW_DAYS')
    example.run
  ensure
    if previous_value.nil?
      ENV.delete('CRM_KANBAN_ENABLED')
    else
      ENV['CRM_KANBAN_ENABLED'] = previous_value
    end
    if previous_dedup_window.nil?
      ENV.delete('CRM_AUTO_CREATE_DEDUP_WINDOW_DAYS')
    else
      ENV['CRM_AUTO_CREATE_DEDUP_WINDOW_DAYS'] = previous_dedup_window
    end
  end

  before do
    allow(Crm::Cards::Broadcaster).to receive(:broadcast)
  end

  it 'does not create cards when the CRM feature flag is disabled' do
    account, admin = create_account_and_user
    inbox = create_crm_inbox(account: account, members: [admin])
    contact = account.contacts.create!(name: 'Lead Sem Flag', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: admin)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: stage, auto_create_card: true, created_by: admin)
    message = create_crm_message(conversation: conversation, sender: contact)
    ENV['CRM_KANBAN_ENABLED'] = 'false'

    described_class.new(conversation: conversation, message: message).perform

    expect(account.crm_cards).to be_blank
    expect(Crm::Cards::Broadcaster).not_to have_received(:broadcast)
  end

  # #2084: contato marcado parceiro do mercado ou não é negócio não ganha card sozinho.
  describe 'with contato_relacao' do
    def cenario(relacao)
      account, admin = create_account_and_user
      account.enable_features!('contato_relacao')
      inbox = create_crm_inbox(account: account, members: [admin])
      contact = account.contacts.create!(name: 'Fornecedor', phone_number: '+5511987654321', relacao: relacao)
      conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: admin)
      pipeline, stage = create_crm_pipeline(account: account, user: admin)
      account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: stage, auto_create_card: true, created_by: admin)
      [account, conversation, create_crm_message(conversation: conversation, sender: contact), pipeline, stage]
    end

    %i[parceiro nao_e_negocio].each do |relacao|
      it "does not auto-create a card for a contact marked #{relacao}" do
        account, conversation, message = cenario(relacao)

        described_class.new(conversation: conversation, message: message).perform

        expect(account.crm_cards).to be_blank
      end
    end

    it 'keeps the card made by hand following the conversation of a contact marked parceiro' do
      account, conversation, message, pipeline, stage = cenario(:parceiro)
      feito_a_mao = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: conversation.contact,
                                              inbox: conversation.inbox, title: 'Feito à mão')

      described_class.new(conversation: conversation, message: message).perform

      expect(account.crm_cards).to contain_exactly(feito_a_mao)
      expect(Crm::CardConversation.where(card: feito_a_mao, conversation: conversation)).to exist
    end

    it 'still auto-creates the card for an interessado contact' do
      account, conversation, message = cenario(:interessado)

      described_class.new(conversation: conversation, message: message).perform

      expect(account.crm_cards.count).to eq(1)
    end
  end

  # #2395: o "não é negócio" da IA não volta a cada mensagem (do cliente, da equipe ou do robô); e a conversa do conector
  # do WhatsApp (avisos de QR, vínculo) não vira card nem é ligada a um.
  describe 'o que não cria card sozinho (#2395)' do
    let(:account) { create_account_and_user.first }
    let(:admin) { account.users.first }
    let(:inbox) { create_crm_inbox(account: account, members: [admin]) }
    let(:contact) { account.contacts.create!(name: 'Lead', phone_number: '+5511987654321') }
    let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
    let!(:pipeline_e_etapa) do
      pipeline, stage = create_crm_pipeline(account: account, user: admin)
      account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: stage, auto_create_card: true, created_by: admin)
      [pipeline, stage]
    end

    def sincronizar(message)
      described_class.new(conversation: conversation, message: message).perform
    end

    def arquivar(card, payload)
      Crm::Cards::Archiver.new(card: card, actor: payload.delete(:actor), payload: payload).perform
    end

    def card_arquivado(**payload)
      card = sincronizar(create_crm_message(conversation: conversation, sender: contact))
      arquivar(card, payload)
      card
    end

    it 'não recria o card que a IA arquivou como "não é negócio", nem com a mensagem do cliente' do
      card_arquivado(by: 'ai', motivo: 'fora_do_negocio')

      expect { sincronizar(create_crm_message(conversation: conversation, sender: contact)) }.not_to change(Crm::Card, :count)
    end

    it 'volta a criar quando o arquivamento da IA tem mais de 30 dias' do
      card = card_arquivado(by: 'ai', motivo: 'fora_do_negocio')
      Crm::Activity.where(card: card, event_type: 'archive').update_all(created_at: 31.days.ago) # rubocop:disable Rails/SkipsModelValidations

      expect { sincronizar(create_crm_message(conversation: conversation, sender: contact)) }.to change(Crm::Card, :count).by(1)
    end

    it 'cria de novo quando quem arquivou foi uma pessoa' do
      card_arquivado(actor: admin)

      expect { sincronizar(create_crm_message(conversation: conversation, sender: contact)) }.to change(Crm::Card, :count).by(1)
    end

    it 'cria de novo quando a IA arquivou por repetido (o motivo é outro)' do
      card_arquivado(by: 'ai', motivo: 'duplicado')

      expect { sincronizar(create_crm_message(conversation: conversation, sender: contact)) }.to change(Crm::Card, :count).by(1)
    end

    it 'cria de novo quando a pessoa reabriu e arquivou o card depois da IA' do
      card = card_arquivado(by: 'ai', motivo: 'fora_do_negocio')
      card.update!(status: :open)
      arquivar(card, { actor: admin })

      expect { sincronizar(create_crm_message(conversation: conversation, sender: contact)) }.to change(Crm::Card, :count).by(1)
    end

    it 'volta a criar quando o card mais novo da conversa nasceu depois do arquivamento (o do assunto novo) e fechou' do
      card_arquivado(by: 'ai', motivo: 'fora_do_negocio')
      pipeline, stage = pipeline_e_etapa
      novo = Crm::Cards::Creator.new(account: account, user: nil, conversation: conversation,
                                     params: { pipeline_id: pipeline.id, stage_id: stage.id }).perform
      novo.update!(status: :lost, closed_at: Time.current)

      expect { sincronizar(create_crm_message(conversation: conversation, sender: contact)) }.to change(Crm::Card, :count).by(1)
    end

    it 'depois do arquivamento, nem a mensagem da equipe nem a do robô recriam o card' do
      card_arquivado(by: 'ai', motivo: 'fora_do_negocio')
      da_equipe = create_crm_message(conversation: conversation, sender: admin, message_type: :outgoing)
      robo = AgentBot.create!(name: 'Robô', account: account)
      do_robo = create_crm_message(conversation: conversation, sender: robo, message_type: :outgoing)

      expect do
        sincronizar(da_equipe)
        sincronizar(do_robo)
      end.not_to change(Crm::Card, :count)
    end

    it 'sem arquivamento, a mensagem da equipe cria card como antes' do
      da_equipe = create_crm_message(conversation: conversation, sender: admin, message_type: :outgoing)

      expect { sincronizar(da_equipe) }.to change(Crm::Card, :count).by(1)
    end

    describe 'conversa do conector do WhatsApp (avisos de QR e de vínculo)' do
      before { contact.update!(identifier: Waha::IntegracaoDoConector::IDENTIFIER) }

      it 'não cria card' do
        expect { sincronizar(create_crm_message(conversation: conversation, sender: contact)) }.not_to change(Crm::Card, :count)
      end

      it 'não liga a conversa ao card aberto do contato' do
        pipeline, stage = pipeline_e_etapa
        aberto = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, inbox: inbox, title: 'Feito à mão')

        sincronizar(create_crm_message(conversation: conversation, sender: contact))

        expect(Crm::CardConversation.where(card: aberto, conversation: conversation)).not_to exist
        expect(aberto.reload.conversation_id).to be_nil
      end
    end
  end

  it 'does not create cards for inboxes without auto-create binding' do
    account, admin = create_account_and_user
    inbox = create_crm_inbox(account: account, members: [admin])
    contact = account.contacts.create!(name: 'Lead Sem Auto', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: admin)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: stage, auto_create_card: false, created_by: admin)
    message = create_crm_message(conversation: conversation, sender: contact)

    described_class.new(conversation: conversation, message: message).perform

    expect(account.crm_cards).to be_blank
  end

  it 'does not create cards when inbox CRM settings disable CRM' do
    account, admin = create_account_and_user
    inbox = create_crm_inbox(account: account, members: [admin])
    contact = account.contacts.create!(name: 'Lead CRM Off', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: admin)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: stage, auto_create_card: true, created_by: admin)
    account.crm_inbox_settings.create!(inbox: inbox, crm_enabled: false, auto_create_card: true)
    message = create_crm_message(conversation: conversation, sender: contact)

    described_class.new(conversation: conversation, message: message).perform

    expect(account.crm_cards).to be_blank
  end

  it 'does not create cards when inbox CRM settings disable auto-create' do
    account, admin = create_account_and_user
    inbox = create_crm_inbox(account: account, members: [admin])
    contact = account.contacts.create!(name: 'Lead Auto Off', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: admin)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: stage, auto_create_card: true, created_by: admin)
    account.crm_inbox_settings.create!(inbox: inbox, crm_enabled: true, auto_create_card: false)
    message = create_crm_message(conversation: conversation, sender: contact)

    described_class.new(conversation: conversation, message: message).perform

    expect(account.crm_cards).to be_blank
  end

  context 'when the inbox does not auto-create cards but an automation already created one' do
    let(:account) { create_account_and_user.first }
    let(:agent) { create_crm_agent(account: account, name: 'Ana Rodízio').first }
    let(:inbox) { create_crm_inbox(account: account, members: [agent]) }
    let(:contact) { account.contacts.create!(name: 'Lead do Formulário', phone_number: '+5511987654321') }
    let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
    let(:card) do
      _pipeline, stage = create_crm_pipeline(account: account, user: agent)
      Crm::Cards::Creator.new(account: account, user: nil, conversation: conversation,
                              params: { pipeline_id: stage.pipeline_id, stage_id: stage.id }).perform
    end

    before { account.crm_inbox_settings.create!(inbox: inbox, crm_enabled: true, auto_create_card: false) }

    it 'gives the card the agent the conversation was assigned to afterwards' do
      expect(card.owner_id).to be_nil
      conversation.update!(assignee: agent)

      described_class.new(conversation: conversation.reload).perform

      expect(card.reload.owner_id).to eq(agent.id)
      expect(card.metadata.dig('crm_auto_sync', 'source')).to be_nil
      expect(Crm::Cards::Broadcaster).to have_received(:broadcast).with(card, Events::Types::CRM_CARD_UPDATED)
    end

    it 'keeps an owner someone already chose on the card' do
      other_agent, = create_crm_agent(account: account, name: 'Bruno Escolhido')
      card.update!(owner: other_agent)
      conversation.update!(assignee: agent)

      described_class.new(conversation: conversation.reload).perform

      expect(card.reload.owner_id).to eq(other_agent.id)
    end

    it 'does not touch the card when CRM is off for the inbox' do
      card
      account.crm_inbox_settings.find_by(inbox: inbox).update!(crm_enabled: false)
      conversation.update!(assignee: agent)

      described_class.new(conversation: conversation.reload).perform

      expect(card.reload.owner_id).to be_nil
    end

    # Fora do card automático, a mensagem não mexe no card: avançar a atividade faria o StaleCardsJob reavaliar o card
    # com IA paga a cada período parado, e cada mensagem abriria lock de conversa e contato à toa.
    it 'leaves the card alone on a new message, without locking or scheduling AI' do
      card.update!(last_activity_at: 2.days.ago, last_message_at: 2.days.ago)
      before_activity = card.reload.last_activity_at
      message = create_crm_message(conversation: conversation, sender: contact)
      allow(Crm::Conversations::SyncLock).to receive(:new).and_call_original
      allow(Crm::Ai::Observer).to receive(:new).and_call_original

      described_class.new(conversation: conversation, message: message).perform

      expect(card.reload.last_activity_at.to_i).to eq(before_activity.to_i)
      expect(Crm::Conversations::SyncLock).not_to have_received(:new)
      expect(Crm::Ai::Observer).not_to have_received(:new)
    end

    it 'does not lock the conversation when there is no card to update' do
      conversation.update!(assignee: agent)
      allow(Crm::Conversations::SyncLock).to receive(:new).and_call_original

      described_class.new(conversation: conversation.reload).perform

      expect(Crm::Conversations::SyncLock).not_to have_received(:new)
      expect(account.crm_cards).to be_blank
    end
  end

  # rubocop:disable RSpec/MultipleExpectations
  it 'creates one hydrated card for an auto-create inbox binding' do
    account, admin = create_account_and_user
    agent, = create_crm_agent(account: account)
    team = account.teams.create!(name: 'Vendas')
    inbox = create_crm_inbox(account: account, members: [agent])
    contact = account.contacts.create!(name: 'Maria Auto', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: agent, team: team)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: stage, auto_create_card: true, created_by: admin)
    message = create_crm_message(conversation: conversation, sender: contact)
    conversation.update!(assignee: agent, team: team)

    card = described_class.new(conversation: conversation, message: message).perform

    expect(card).to be_persisted
    expect(account.crm_cards.count).to eq(1)
    expect(card.pipeline_id).to eq(pipeline.id)
    expect(card.stage_id).to eq(stage.id)
    expect(card.contact_id).to eq(contact.id)
    expect(card.conversation_id).to eq(conversation.id)
    expect(card.inbox_id).to eq(inbox.id)
    expect(card.owner_id).to eq(agent.id)
    expect(card.team_id).to eq(team.id)
    expect(card.title).to eq('Maria Auto')
    expect(card.last_message_at.to_i).to eq(message.created_at.to_i)
    expect(card.metadata.dig('crm_auto_sync', 'source')).to eq('conversation_observer')
    expect(account.crm_card_conversations.where(card: card, conversation: conversation)).to exist
    expect(account.crm_activities.where(card: card, event_type: 'create')).to exist
    expect(Crm::Cards::Broadcaster).to have_received(:broadcast).with(card, Events::Types::CRM_CARD_CREATED)
  end
  # rubocop:enable RSpec/MultipleExpectations

  it 'reuses the same active card on retries' do
    account, admin = create_account_and_user
    inbox = create_crm_inbox(account: account, members: [admin])
    contact = account.contacts.create!(name: 'Lead Retry', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: admin)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: stage, auto_create_card: true, created_by: admin)
    message = create_crm_message(conversation: conversation, sender: contact)

    first_card = described_class.new(conversation: conversation, message: message).perform
    second_card = described_class.new(conversation: conversation, message: message).perform

    expect(second_card.id).to eq(first_card.id)
    expect(account.crm_cards.where(conversation_id: conversation.id).count).to eq(1)
    expect(account.crm_card_conversations.where(conversation_id: conversation.id).count).to eq(1)
  end

  it 'reuses an open card with the same contact, inbox and pipeline inside the dedup window' do
    account, admin = create_account_and_user
    inbox = create_crm_inbox(account: account, members: [admin])
    contact = account.contacts.create!(name: 'Lead Dedupe', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: admin)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    existing_card = account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      contact: contact,
      inbox: inbox,
      owner: admin,
      title: 'Lead Dedupe Existente',
      last_activity_at: 2.days.ago
    )
    account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: stage, auto_create_card: true, created_by: admin)
    message = create_crm_message(conversation: conversation, sender: contact)

    card = described_class.new(conversation: conversation, message: message).perform

    expect(card.id).to eq(existing_card.id)
    expect(account.crm_cards.open.where(contact: contact, inbox: inbox, pipeline: pipeline).count).to eq(1)
    expect(card.reload.conversation_id).to eq(conversation.id)
    expect(account.crm_card_conversations.where(card: card, conversation: conversation)).to exist
    expect(card.activities.where(event_type: 'conversation_dedup_reuse')).to exist
  end

  it 'does not reuse contact/inbox/pipeline cards outside the configured dedup window' do
    ENV['CRM_AUTO_CREATE_DEDUP_WINDOW_DAYS'] = '1'
    account, admin = create_account_and_user
    inbox = create_crm_inbox(account: account, members: [admin])
    contact = account.contacts.create!(name: 'Lead Fora Janela', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: admin)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    old_card = account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      contact: contact,
      inbox: inbox,
      title: 'Lead Antigo',
      last_activity_at: 3.days.ago
    )
    account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: stage, auto_create_card: true, created_by: admin)
    message = create_crm_message(conversation: conversation, sender: contact)

    card = described_class.new(conversation: conversation, message: message).perform

    expect(card.id).not_to eq(old_card.id)
    expect(account.crm_cards.open.where(contact: contact, inbox: inbox, pipeline: pipeline).count).to eq(2)
  end

  it 'does not reuse won or lost cards for automatic creation' do
    account, admin = create_account_and_user
    inbox = create_crm_inbox(account: account, members: [admin])
    contact = account.contacts.create!(name: 'Lead Fechado', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: admin)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    lost_card = account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      contact: contact,
      inbox: inbox,
      title: 'Lead Perdido',
      status: :lost,
      last_activity_at: 1.hour.ago
    )
    account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: stage, auto_create_card: true, created_by: admin)
    message = create_crm_message(conversation: conversation, sender: contact)

    card = described_class.new(conversation: conversation, message: message).perform

    expect(card.id).not_to eq(lost_card.id)
    expect(card).to be_open
    expect(account.crm_cards.where(contact: contact, inbox: inbox, pipeline: pipeline).count).to eq(2)
  end

  it 'refreshes an existing auto-created card when the conversation changes' do
    account, admin = create_account_and_user
    first_agent, = create_crm_agent(account: account, name: 'Primeiro agente')
    next_agent, = create_crm_agent(account: account, name: 'Segundo agente')
    team = account.teams.create!(name: 'Suporte')
    inbox = create_crm_inbox(account: account, members: [first_agent, next_agent])
    contact = account.contacts.create!(name: 'Lead Atualizado', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: first_agent)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: stage, auto_create_card: true, created_by: admin)
    first_message = create_crm_message(conversation: conversation, sender: contact, content: 'Primeira mensagem')
    card = described_class.new(conversation: conversation, message: first_message).perform

    conversation.update!(assignee: next_agent, team: team)
    next_message = create_crm_message(conversation: conversation, sender: contact, content: 'Nova mensagem')
    conversation.update!(assignee: next_agent, team: team)
    described_class.new(conversation: conversation.reload, message: next_message).perform

    card.reload
    expect(card.owner_id).to eq(next_agent.id)
    expect(card.team_id).to eq(team.id)
    expect(card.last_message_at.to_i).to eq(next_message.created_at.to_i)
    expect(card.activities.where(event_type: 'conversation_sync')).to exist
    expect(Crm::Cards::Broadcaster).to have_received(:broadcast).with(card, Events::Types::CRM_CARD_UPDATED)
  end

  it 'prefers the inbox default pipeline when multiple auto-create bindings exist' do
    account, admin = create_account_and_user
    inbox = create_crm_inbox(account: account, members: [admin])
    contact = account.contacts.create!(name: 'Lead Preferido', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: admin)
    first_pipeline, first_stage = create_crm_pipeline(account: account, user: admin, name: 'Funil A')
    second_pipeline, second_stage = create_crm_pipeline(account: account, user: admin, name: 'Funil B')
    account.crm_pipeline_inboxes.create!(
      pipeline: first_pipeline, inbox: inbox, default_stage: first_stage, auto_create_card: true, created_by: admin
    )
    account.crm_pipeline_inboxes.create!(
      pipeline: second_pipeline, inbox: inbox, default_stage: second_stage, auto_create_card: true, created_by: admin
    )
    account.crm_inbox_settings.create!(
      inbox: inbox,
      crm_enabled: true,
      auto_create_card: true,
      default_pipeline: second_pipeline,
      default_stage: second_stage
    )
    message = create_crm_message(conversation: conversation, sender: contact)

    card = described_class.new(conversation: conversation, message: message).perform

    expect(card.pipeline_id).to eq(second_pipeline.id)
    expect(card.stage_id).to eq(second_stage.id)
  end

  # Reason: assignee_changed/team_changed listeners enqueue CardSyncer with
  # message: nil (Crm::SyncConversationCardJob#perform default). Without a NEW
  # real message since the card was created, last_message_at/last_activity_at
  # must stay put — this was the root cause bug (fallback to conversation.
  # last_activity_at, which any system activity message bumps).
  it 'does not alter last_message_at/last_activity_at when syncing without a message' do
    account, admin = create_account_and_user
    agent, = create_crm_agent(account: account)
    inbox = create_crm_inbox(account: account, members: [agent])
    contact = account.contacts.create!(name: 'Lead Sem Mensagem Nova', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: agent)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: stage, auto_create_card: true, created_by: admin)
    message = create_crm_message(conversation: conversation, sender: contact)
    card = described_class.new(conversation: conversation, message: message).perform
    original_last_message_at = card.last_message_at
    original_last_activity_at = card.last_activity_at

    other_agent, = create_crm_agent(account: account, name: 'Outro agente')
    conversation.update!(assignee: other_agent)
    described_class.new(conversation: conversation.reload, message: nil).perform

    card.reload
    expect(card.owner_id).to eq(other_agent.id)
    expect(card.last_message_at.to_i).to eq(original_last_message_at.to_i)
    expect(card.last_activity_at.to_i).to eq(original_last_activity_at.to_i)
  end

  # Reason: stage moves and linkers set last_activity_at to Time.current; a later
  # assignment sync (message: nil) deriving from the last real message would
  # regress that recent CRM activity back to an old message date, breaking
  # ordering and dedupe. The sync must leave both fields untouched.
  it 'does not regress a recent last_activity_at to an old real-message date on message-less sync' do
    account, admin = create_account_and_user
    agent, = create_crm_agent(account: account)
    inbox = create_crm_inbox(account: account, members: [agent])
    contact = account.contacts.create!(name: 'Lead Atividade Recente', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: agent)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: stage, auto_create_card: true, created_by: admin)
    old_message = travel_to(5.days.ago) { create_crm_message(conversation: conversation, sender: contact, content: 'Mensagem antiga') }
    card = described_class.new(conversation: conversation, message: old_message).perform
    card.update!(last_activity_at: Time.current)
    recent_activity_at = card.reload.last_activity_at

    other_agent, = create_crm_agent(account: account, name: 'Outro agente')
    conversation.update!(assignee: other_agent)
    described_class.new(conversation: conversation.reload, message: nil).perform

    card.reload
    expect(card.last_activity_at.to_i).to eq(recent_activity_at.to_i)
    expect(card.last_message_at.to_i).to eq(old_message.created_at.to_i)
  end

  # Reason: a private note or an activity message (system-generated, e.g. an
  # assignment note) must never count as a real message even if it were ever
  # passed in as @message — CardSyncer derives last_message_at purely from
  # Message.chat on the conversation, ignoring @message's own timestamp.
  it 'does not count an activity message towards last_message_at' do
    account, admin = create_account_and_user
    agent, = create_crm_agent(account: account)
    inbox = create_crm_inbox(account: account, members: [agent])
    contact = account.contacts.create!(name: 'Lead Activity', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: agent)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: stage, auto_create_card: true, created_by: admin)
    real_message = travel_to(2.minutes.ago) { create_crm_message(conversation: conversation, sender: contact, content: 'Mensagem real') }
    card = described_class.new(conversation: conversation, message: real_message).perform

    activity_message = create_crm_message(
      conversation: conversation, sender: contact, content: 'Assignee mudou', message_type: :activity
    )
    described_class.new(conversation: conversation.reload, message: activity_message).perform

    card.reload
    expect(card.last_message_at.to_i).to eq(real_message.created_at.to_i)
    expect(card.last_message_at.to_i).not_to eq(activity_message.created_at.to_i)
  end

  def create_crm_message(conversation:, sender:, content: 'Olá', private: false, message_type: :incoming)
    conversation.messages.create!(
      account: conversation.account,
      inbox: conversation.inbox,
      sender: sender,
      content: content,
      message_type: message_type,
      private: private
    )
  end
  # #1273: conversa NOVA, ainda sem atendente, reaproveita o card criado automaticamente de outra conversa do contato.
  # O card não pode perder o dono só porque a conversa nova ainda não foi distribuída.
  it 'keeps the owner of a reused auto-created card when the new conversation has no assignee yet' do
    account, admin = create_account_and_user
    inbox = create_crm_inbox(account: account, members: [admin])
    contact = account.contacts.create!(name: 'Lead Volta', phone_number: '+5511987650001')
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: stage, auto_create_card: true, created_by: admin)
    first = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: admin)
    card = described_class.new(conversation: first, message: create_crm_message(conversation: first, sender: contact)).perform
    expect(card.reload.owner).to eq(admin)

    second = create_crm_conversation(account: account, inbox: inbox, contact: contact)
    reused = described_class.new(conversation: second, message: create_crm_message(conversation: second, sender: contact)).perform

    expect(reused.id).to eq(card.id)
    expect(card.reload.owner).to eq(admin)
  end

  it 'still mirrors the assignee of the card own conversation, set and cleared' do
    account, admin = create_account_and_user
    inbox = create_crm_inbox(account: account, members: [admin])
    contact = account.contacts.create!(name: 'Lead Espelho', phone_number: '+5511987650002')
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: stage, auto_create_card: true, created_by: admin)
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: admin)
    card = described_class.new(conversation: conversation, message: create_crm_message(conversation: conversation, sender: contact)).perform

    expect(card.reload.owner).to eq(admin)

    conversation.update!(assignee: nil)
    described_class.new(conversation: conversation.reload).perform

    expect(card.reload.owner).to be_nil
  end

  describe 'another conversation of the contact reusing the auto-created card (#1273)' do
    let(:account_and_admin) { create_account_and_user }
    let(:account) { account_and_admin.first }
    let(:admin) { account_and_admin.last }
    let(:other_agent) { create(:user, account: account, role: :agent) }
    let(:inbox) { create_crm_inbox(account: account, members: [admin, other_agent]) }
    let(:contact) { account.contacts.create!(name: 'Lead Duas Conversas', phone_number: '+5511987650003') }
    let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }

    before do
      pipeline, stage = pipeline_and_stage
      account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: stage, auto_create_card: true, created_by: admin)
    end

    def sync(conversation)
      described_class.new(conversation: conversation, message: create_crm_message(conversation: conversation, sender: contact)).perform
    end

    it 'does not overwrite owner nor team with another agent and team' do
      first_team = create(:team, account: account)
      other_team = create(:team, account: account)
      # Chatwoot tira o atendente que não é do time da conversa.
      create(:team_member, team: first_team, user: admin)
      create(:team_member, team: other_team, user: other_agent)
      card = sync(create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: admin, team: first_team))

      sync(create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: other_agent, team: other_team))

      expect(card.reload).to have_attributes(owner_id: admin.id, team_id: first_team.id)
    end

    it 'fills an empty owner and team' do
      team = create(:team, account: account)
      create(:team_member, team: team, user: other_agent)
      card = sync(create_crm_conversation(account: account, inbox: inbox, contact: contact))
      expect(card.reload.owner).to be_nil

      sync(create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: other_agent, team: team))

      expect(card.reload).to have_attributes(owner_id: other_agent.id, team_id: team.id)
    end
  end
end

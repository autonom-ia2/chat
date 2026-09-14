require 'rails_helper'

RSpec.describe Crm::FollowUps::AutoFollowupRunner do
  let(:now) { Time.current }
  # Composition the AI brain would return: send, no closure, confident, template #0 chosen.
  let(:composition) do
    {
      'should_send' => true,
      'closure_detected' => false,
      'confidence' => 0.9,
      'message_body' => 'Olá, tudo bem?',
      'chosen_template' => { 'index' => 0 },
      'template_variables' => {}
    }
  end
  # Frase gravada na conversa; a citação da IA precisa sair daqui.
  let(:transcript_line) { 'Enviei um questionário para a análise da seguradora, e te retorno com um orçamento.' }
  # A vez é nossa (ou de um terceiro): a IA avisa o andamento em vez de cobrar.
  let(:status_notice) do
    {
      'should_send' => true, 'closure_detected' => false, 'confidence' => 0.9,
      'next_action_owner' => 'terceiro', 'message_kind' => 'aviso_andamento',
      'open_loop' => 'Orçamento prometido, aguardando a seguradora',
      'open_loop_source' => transcript_line,
      'message_body' => 'Ainda estou com a seguradora; assim que retornar eu te trago o orçamento.'
    }
  end

  before do
    travel_to Time.utc(2026, 9, 14, 15)
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
  end

  def seed_transcript_line(follow_up)
    follow_up.conversation.messages.incoming.last.update!(content: transcript_line)
  end

  def native_candidate(category)
    { kind: 'native', name: "tpl_#{category}", id: nil, language: 'pt_BR',
      body: 'Oi {{1}}', variables: ['1'], category: category }
  end

  # Non-WAHA WhatsApp API campaign inbox so the 24h window applies and the runner
  # picks :choose_template mode (WAHA is window-free → free_form).
  def outside_window_setup
    account, user = create_account_and_user
    inbox = create_crm_whatsapp_api_inbox(account: account, members: [user])
    inbox.channel.enable_whatsapp_api_campaigns!(provider: 'cloud')
    contact = account.contacts.create!(name: 'Lead', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: user)
    create_incoming_message(conversation: conversation)
    conversation.messages.incoming.last.update!(created_at: 30.hours.ago)
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    pipeline.update!(metadata: { ai: { auto_followup: { enabled: true } } })
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, inbox: inbox,
                                     contact: contact, primary_conversation: conversation, title: 'Lead')
    [account, user, contact, conversation, card]
  end

  # A prior MARKETING template already delivered to this contact 1h ago (within the cap window).
  def seed_prior_marketing_send(account:, card:, conversation:, contact:, user:)
    account.crm_follow_ups.create!(
      card: card, conversation: conversation, contact: contact, title: 'Toque anterior',
      due_at: 2.hours.ago, timezone: 'UTC', status: :done, automation_mode: :auto_send_message, created_by: user,
      metadata: { 'source' => 'ai_followup', 'send_mode' => 'template', 'message_body' => 'anterior',
                  'template_category' => 'marketing', 'sent_at' => (now - 1.hour).iso8601 }
    )
  end

  def build_follow_up(account:, card:, conversation:, user:, contact:)
    account.crm_follow_ups.create!(
      card: card, conversation: conversation, contact: contact, title: 'Retornar',
      due_at: 10.minutes.ago, timezone: 'UTC', automation_mode: :auto_send_message, created_by: user,
      metadata: { 'source' => 'ai_followup', 'touch' => 1, 'message_body' => 'rascunho' }
    )
  end

  def run_with_candidate(candidate, follow_up)
    runner = described_class.new(follow_up: follow_up, now: now)
    allow(runner).to receive(:compose).and_return(composition)
    allow(runner).to receive(:template_candidates).and_return([candidate])
    runner.perform
  end

  it 'caps a MARKETING template sent within 24h to the same contact (reschedules the touch)' do
    account, user, contact, conversation, card = outside_window_setup
    seed_prior_marketing_send(account: account, card: card, conversation: conversation, contact: contact, user: user)
    follow_up = build_follow_up(account: account, card: card, conversation: conversation, user: user, contact: contact)

    # No message should be created while capped (the runner short-circuits before the sender).
    result = nil
    expect { result = run_with_candidate(native_candidate('marketing'), follow_up) }
      .not_to change(Message, :count)

    expect(result.status).to eq(:rescheduled)
    expect(follow_up.reload.due_at).to be > now + 20.hours
    expect(follow_up.metadata['template_category']).to eq('marketing')
  end

  it 'does NOT cap a UTILITY template even with a recent marketing send to the same contact' do
    account, user, contact, conversation, card = outside_window_setup
    seed_prior_marketing_send(account: account, card: card, conversation: conversation, contact: contact, user: user)
    follow_up = build_follow_up(account: account, card: card, conversation: conversation, user: user, contact: contact)
    # Utility escapes the cap → it must reach the sender (stubbed to skip the real send).
    sender = instance_double(Crm::FollowUps::MessageSender, perform: Crm::FollowUps::MessageSender::Result.skipped)
    allow(Crm::FollowUps::MessageSender).to receive(:new).and_return(sender)

    result = run_with_candidate(native_candidate('utility'), follow_up)

    expect(result.status).not_to eq(:rescheduled)
    expect(result.status).to eq(:skipped)
    expect(follow_up.reload.metadata['template_category']).to eq('utility')
  end

  def stub_credential
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(
      instance_double(Crm::Ai::CredentialResolver,
                      resolve: { api_key: 'sk-test', api_base: 'https://api.openai.com', source: :system })
    )
  end

  def stub_composition(payload)
    allow(Crm::Ai::FollowUpComposer).to receive(:new)
      .and_return(instance_double(Crm::Ai::FollowUpComposer, perform: payload))
  end

  it 'sends the status notice once and records it on the card' do
    account, user = create_account_and_user
    follow_up = setup_followup(account: account, user: user)
    seed_transcript_line(follow_up)
    stub_credential
    stub_composition(status_notice)
    allow(Crm::FollowUps::MessageSender).to receive(:new).and_return(
      instance_double(Crm::FollowUps::MessageSender, perform: Crm::FollowUps::MessageSender::Result.sent(nil))
    )

    result = described_class.new(follow_up: follow_up, now: Time.current).perform

    expect(result.status).to eq(:sent)
    expect(follow_up.reload.metadata['message_kind']).to eq('aviso_andamento')
    expect(follow_up.metadata['open_loop_source']).to eq(transcript_line)
    expect(follow_up.card.reload.metadata['ai']['auto_followup_state']['status_notice_sent']).to be(true)
  end

  # O caso real: a IA "cita" algo que soa literal mas não está na conversa (o questionário foi para
  # a seguradora, não para o cliente). Sem conferência isso virava mensagem enviada.
  it 'refuses to send when the cited quote is not in the transcript' do
    account, user = create_account_and_user
    follow_up = setup_followup(account: account, user: user)
    seed_transcript_line(follow_up)
    stub_credential
    stub_composition(status_notice.merge('open_loop_source' => 'conseguiu acessar o questionário que te enviei?'))

    result = nil
    expect { result = described_class.new(follow_up: follow_up, now: Time.current).perform }
      .not_to change(Message, :count)

    expect(result.status).to eq(:failed)
    expect(result.error.to_s).to include('unverified_quote')
    expect(follow_up.reload.metadata['retries']).to eq(1)
  end

  # Citação não conferida gasta o mesmo orçamento de tentativas de uma falha de rede, mas precisa
  # ficar registrada com o próprio nome — senão vira "send_failed" e ninguém investiga o certo.
  it 'finalizes with its own reason when the quote never checks out' do
    account, user = create_account_and_user
    follow_up = setup_followup(account: account, user: user)
    seed_transcript_line(follow_up)
    follow_up.update!(metadata: follow_up.metadata.merge('retries' => 2))
    stub_credential
    stub_composition(status_notice.merge('open_loop_source' => 'frase que nunca foi dita nesta conversa'))

    result = described_class.new(follow_up: follow_up, now: Time.current).perform

    expect(result.status).to eq(:failed_final)
    expect(follow_up.card.reload.metadata['ai']['auto_followup_state']['stopped_reason']).to eq('unverified_quote')
  end

  it 'stays quiet on a second status notice for the same card' do
    account, user = create_account_and_user
    follow_up = setup_followup(account: account, user: user)
    seed_transcript_line(follow_up)
    card = follow_up.card
    card.update!(metadata: { 'ai' => { 'auto_followup_state' => { 'status_notice_sent' => true } } })
    stub_credential
    stub_composition(status_notice)

    result = nil
    expect { result = described_class.new(follow_up: follow_up, now: Time.current).perform }
      .not_to change(Message, :count)

    expect(result.status).to eq(:skipped)
    expect(card.reload.metadata['ai']['auto_followup_state']['stopped_reason']).to eq('status_notice_already_sent')
  end

  def setup_followup(account:, user:)
    inbox = create_crm_whatsapp_api_inbox(account: account, members: [user])
    contact = account.contacts.create!(name: 'Lead', phone_number: "+55119#{rand(10_000_000..99_999_999)}")
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: user)
    create_incoming_message(conversation: conversation)
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    pipeline.update!(metadata: { ai: { auto_followup: { enabled: true } } })
    card = account.crm_cards.create!(
      pipeline: pipeline, stage: stage, inbox: inbox, contact: contact,
      primary_conversation: conversation, title: 'Lead'
    )
    account.crm_follow_ups.create!(
      card: card, conversation: conversation, title: 'Retomar', due_at: 10.minutes.ago, timezone: 'UTC',
      automation_mode: :auto_send_message, created_by: user,
      metadata: { source: 'ai_followup', touch: 1, message_body: 'Olá' }
    )
  end

  # (B) CREDENTIAL FAIL-CLOSED: a nil credential must become a rescued transient
  # (Result :failed with a retry_at), NOT an unrescued NoMethodError from
  # ResponsesClient dereferencing a nil @credential.
  it 'returns a rescued transient failure (not a NoMethodError) when the credential is nil' do
    account, user = create_account_and_user
    follow_up = setup_followup(account: account, user: user)
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: nil))

    result = nil
    expect { result = described_class.new(follow_up: follow_up, now: Time.current).perform }.not_to raise_error

    expect(result.status).to eq(:failed)
    expect(result.retry_at).to be_present
    expect(follow_up.reload.metadata['retries']).to eq(1)
  end

  # Control: with a present credential the compose path runs normally — the guard
  # does not misfire — and a "don't send" composition yields a clean :skipped.
  it 'composes normally when the credential is present and skips on a no-send decision' do
    account, user = create_account_and_user
    follow_up = setup_followup(account: account, user: user)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(
      instance_double(Crm::Ai::CredentialResolver,
                      resolve: { api_key: 'sk-test', api_base: 'https://api.openai.com', source: :system })
    )
    allow(Crm::Ai::FollowUpComposer).to receive(:new)
      .and_return(instance_double(Crm::Ai::FollowUpComposer, perform: { 'should_send' => false }))

    result = described_class.new(follow_up: follow_up, now: Time.current).perform

    expect(result.status).to eq(:skipped)
  end

  context 'with AI team reminders' do
    def reminder_setup
      account, user = create_account_and_user
      follow_up = setup_followup(account: account, user: user)
      pipeline = follow_up.card.pipeline
      pipeline.update!(metadata: { ai: { auto_followup: {
                         enabled: true, mode: 'ai_reminder', max_touches: 3, intervals_hours: [6, 72, 168],
                         allowed_days: [1, 2, 3, 4, 5], quiet_hours: { start: 8, end: 20, tz: 'contact' }
                       } } })
      seed_transcript_line(follow_up)
      stub_credential
      stub_composition(status_notice)
      follow_up
    end

    it 'uses AI with quote verification, creates a reminder and advances without sending' do
      follow_up = reminder_setup
      expect(Crm::Ai::FollowUpComposer).to receive(:new).with(hash_including(mode: :reminder))
                                                        .and_return(instance_double(Crm::Ai::FollowUpComposer, perform: status_notice))
      expect(Crm::FollowUps::MessageSender).not_to receive(:new)
      expect(Crm::FollowUps::TemplateCandidates).not_to receive(:new)
      result = described_class.new(follow_up: follow_up, now: now).perform
      expect(result.status).to eq(:reminded)
      expect(follow_up.description).to include(status_notice['open_loop'], status_notice['message_body'])
      expect(follow_up.card.follow_ups.where(status: :pending).count).to eq(2)
      expect(follow_up.card.reload.metadata.dig('ai', 'auto_followup_state', 'touches').last['outcome']).to eq('reminded')
    end

    it 'localizes the reminder title using the account language' do
      follow_up = reminder_setup
      follow_up.account.update!(locale: 'pt_BR')
      described_class.new(follow_up: follow_up, now: now).perform
      expect(follow_up.reload.title).to eq('Lembrete da IA 1')
    end

    it 'stops when the card closes during AI evaluation' do
      follow_up = reminder_setup
      composer = instance_double(Crm::Ai::FollowUpComposer)
      allow(Crm::Ai::FollowUpComposer).to receive(:new).and_return(composer)
      allow(composer).to receive(:perform) do
        Crm::Card.find(follow_up.card_id).update!(status: :won)
        status_notice
      end
      result = described_class.new(follow_up: follow_up, now: now).perform
      expect(result.status).to eq(:stopped)
    end

    it 'respects days changed during AI evaluation' do
      follow_up = reminder_setup
      composer = instance_double(Crm::Ai::FollowUpComposer)
      allow(Crm::Ai::FollowUpComposer).to receive(:new).and_return(composer)
      allow(composer).to receive(:perform) do
        pipeline = Crm::Pipeline.find(follow_up.card.pipeline_id)
        metadata = pipeline.metadata.deep_dup
        metadata['ai']['auto_followup']['allowed_days'] = [2]
        pipeline.update!(metadata: metadata)
        status_notice
      end
      result = described_class.new(follow_up: follow_up, now: now).perform
      expect(result.status).to eq(:rescheduled)
    end

    def during_composition
      composer = instance_double(Crm::Ai::FollowUpComposer)
      allow(Crm::Ai::FollowUpComposer).to receive(:new).and_return(composer)
      allow(composer).to receive(:perform) do
        yield
        status_notice
      end
    end

    def change_followup_config(follow_up, changes)
      pipeline = Crm::Pipeline.find(follow_up.card.pipeline_id)
      data = pipeline.metadata.deep_dup
      data['ai']['auto_followup'].merge!(changes.stringify_keys)
      pipeline.update!(metadata: data)
    end

    it 'preserves cancellation during AI evaluation without notifying or creating another touch' do
      follow_up = reminder_setup
      during_composition { Crm::FollowUp.find(follow_up.id).update!(status: :canceled) }
      expect(Crm::FollowUps::MessageSender).not_to receive(:new)
      expect(Crm::FollowUps::Broadcaster).not_to receive(:broadcast_due)
      expect { Crm::FollowUps::DueProcessor.new(now: now).perform }.not_to change(Crm::FollowUp, :count)
      expect(follow_up.reload).to be_canceled
    end

    it 'stops if the customer replies while AI is evaluating' do
      follow_up = reminder_setup
      during_composition do
        travel 1.second
        create_incoming_message(conversation: follow_up.conversation)
      end
      expect(Crm::FollowUps::MessageSender).not_to receive(:new)
      expect(described_class.new(follow_up: follow_up, now: now).perform.status).to eq(:stopped)
      expect(follow_up.reload.description).to be_blank
    end

    it 'preserves opt-out state written while AI is evaluating' do
      follow_up = reminder_setup
      during_composition do
        card = Crm::Card.find(follow_up.card_id)
        data = card.metadata.deep_dup
        data['ai'] ||= {}
        data['ai']['auto_followup_state'] = { 'opted_out' => true }
        card.update!(metadata: data)
      end
      expect(described_class.new(follow_up: follow_up, now: now).perform.status).to eq(:stopped)
      expect(follow_up.card.reload.metadata.dig('ai', 'auto_followup_state', 'opted_out')).to be(true)
    end

    [false, true].each do |global|
      it "leaves the touch pending when #{global ? 'global AI' : 'the pipeline'} is disabled during evaluation" do
        follow_up = reminder_setup
        during_composition do
          if global
            allow(Crm::Ai::Config).to receive(:enabled?).and_return(false)
          else
            change_followup_config(follow_up, enabled: false)
          end
        end
        expect(Crm::FollowUps::MessageSender).not_to receive(:new)
        expect(described_class.new(follow_up: follow_up, now: now).perform.status).to eq(:rescheduled)
        expect(follow_up.reload).to be_pending
        expect(follow_up.description).to be_blank
      end
    end

    %w[auto_send ai_reminder].each do |initial_mode|
      it "discards the old composition when #{initial_mode} changes during evaluation" do
        follow_up = reminder_setup
        change_followup_config(follow_up, mode: initial_mode)
        follow_up.card.reload
        during_composition do
          change_followup_config(follow_up, mode: initial_mode == 'auto_send' ? 'ai_reminder' : 'auto_send')
        end
        expect(Crm::FollowUps::MessageSender).not_to receive(:new)
        expect(described_class.new(follow_up: follow_up, now: now).perform.status).to eq(:rescheduled)
        expect(follow_up.reload.due_at).to be > now
        expect(follow_up.description).to be_blank
      end
    end

    it 'does not create a reminder when AI declines' do
      follow_up = reminder_setup
      stub_composition(status_notice.merge('should_send' => false))
      expect(Crm::FollowUps::MessageSender).not_to receive(:new)
      expect(described_class.new(follow_up: follow_up, now: now).perform.status).to eq(:skipped)
      expect(follow_up.reload.description).to be_blank
    end

    it 'rejects an invented quote in reminder mode' do
      follow_up = reminder_setup
      stub_composition(status_notice.merge('open_loop_source' => 'invented evidence'))
      expect(described_class.new(follow_up: follow_up, now: now).perform.error).to eq('unverified_quote')
      expect(follow_up.reload.description).to be_blank
    end

    it 'defers a weekend before spending an AI call' do
      follow_up = reminder_setup
      expect(Crm::Ai::FollowUpComposer).not_to receive(:new)
      result = described_class.new(follow_up: follow_up, now: Time.utc(2026, 9, 19, 15)).perform
      expect(result.status).to eq(:rescheduled)
      expect(follow_up.reload.due_at).to eq(Time.utc(2026, 9, 21, 11))
    end

    it 'honors the current mode when a previously scheduled reminder changes to automatic send' do
      follow_up = reminder_setup
      follow_up.update!(automation_mode: :reminder_only)
      pipeline = follow_up.card.pipeline
      data = pipeline.metadata.deep_dup
      data['ai']['auto_followup']['mode'] = 'auto_send'
      pipeline.update!(metadata: data)
      sender = instance_double(Crm::FollowUps::MessageSender, perform: Crm::FollowUps::MessageSender::Result.sent(nil))
      expect(Crm::FollowUps::MessageSender).to receive(:new).and_return(sender)
      expect(described_class.new(follow_up: follow_up, now: now).perform.status).to eq(:sent)
      expect(follow_up.reload).to be_auto_send_message
    end

    it 'requires a template after the official window has expired' do
      account, user, contact, conversation, card = outside_window_setup
      follow_up = build_follow_up(account: account, card: card, conversation: conversation, user: user, contact: contact)
      runner = described_class.new(follow_up: follow_up, now: now)
      allow(runner).to receive(:template_candidates).and_return([])
      allow(runner).to receive(:compose).and_return(composition.merge('chosen_template' => { 'index' => -1 }))
      expect(Crm::FollowUps::MessageSender).not_to receive(:new)
      expect(runner.perform.status).to eq(:skipped)
      expect(follow_up.card.reload.metadata.dig('ai', 'auto_followup_state', 'stopped_reason')).to eq('no_template')
    end

    it 'rechecks allowed hours after a slow AI evaluation' do
      follow_up = reminder_setup
      allow(Crm::Ai::FollowUpComposer).to receive(:new).and_return(
        instance_double(Crm::Ai::FollowUpComposer, perform: status_notice)
      )
      runner = described_class.new(follow_up: follow_up, now: Time.utc(2026, 9, 18, 22, 59))
      allow(runner).to receive(:execution_time).and_return(Time.utc(2026, 9, 18, 23, 1))
      expect(runner.perform.status).to eq(:rescheduled)
      expect(follow_up.reload.description).to be_blank
      expect(follow_up.due_at).to eq(Time.utc(2026, 9, 21, 11))
    end

    it 'keeps a failed Friday evaluation inside the next allowed period' do
      follow_up = reminder_setup
      allow(Crm::Ai::CredentialResolver).to receive(:new)
        .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: nil))
      result = described_class.new(follow_up: follow_up, now: Time.utc(2026, 9, 18, 22, 50)).perform
      expect(result.status).to eq(:failed)
      expect(result.retry_at).to eq(Time.utc(2026, 9, 21, 11))
    end

    it 'keeps the next configured gap when overdue touches would collapse on Monday' do
      follow_up = reminder_setup
      follow_up.conversation.messages.each { |message| message.update!(created_at: 10.days.ago) }
      result = described_class.new(follow_up: follow_up, now: now).perform
      expect(result.status).to eq(:reminded)
      next_touch = follow_up.card.follow_ups.where.not(id: follow_up.id).last
      expect(next_touch.due_at).to be >= now + 66.hours
    end

    it 'stops without a reminder when the customer replies' do
      follow_up = reminder_setup
      follow_up.conversation.messages.incoming.last.update!(created_at: now + 1.minute)
      expect(Crm::Ai::FollowUpComposer).not_to receive(:new)
      expect(described_class.new(follow_up: follow_up, now: now + 2.minutes).perform.status).to eq(:stopped)
    end

    it 'does not evaluate or notify pending reminders when AI is disabled' do
      follow_up = reminder_setup
      follow_up.update!(automation_mode: :reminder_only)
      allow(Crm::Ai::Config).to receive(:enabled?).and_return(false)
      expect(Crm::Ai::FollowUpComposer).not_to receive(:new)
      expect(Crm::FollowUps::Broadcaster).not_to receive(:broadcast_due)
      Crm::FollowUps::DueProcessor.new(now: now).perform
      expect(follow_up.reload).to be_pending
    end

    it 'notifies only after AI approval and does not duplicate on another sweep' do
      follow_up = reminder_setup
      follow_up.update!(automation_mode: :reminder_only)
      allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
      expect(Crm::FollowUps::Broadcaster).to receive(:broadcast_due).with(follow_up).once
      allow(Crm::FollowUps::ReminderNotifier).to receive(:new).and_return(instance_double(Crm::FollowUps::ReminderNotifier, perform: nil))
      expect(Crm::FollowUps::MessageSender).not_to receive(:new)
      2.times { Crm::FollowUps::DueProcessor.new(now: now).perform }
      expect(follow_up.reload).to be_overdue
    end
  end
end

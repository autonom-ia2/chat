require 'rails_helper'

# chat#737: follow-up automático do CRM é envio ativo e respeita a recusa gravada no contato.
# A guarda comum fica no MessageSender; cada chamador trata o resultado do seu jeito.
RSpec.describe 'Recusa de mensagens ativas nos follow-ups do CRM' do # rubocop:disable RSpec/DescribeClass
  let(:transcript_line) { 'Enviei um questionário para a análise da seguradora, e te retorno com um orçamento.' }

  before do
    travel_to Time.utc(2026, 9, 14, 15)
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
  end

  def build_follow_up(metadata:, pipeline_metadata: {})
    account, user = create_account_and_user
    inbox = create_crm_whatsapp_api_inbox(account: account, members: [user])
    contact = account.contacts.create!(name: 'Lead', phone_number: "+55119#{rand(10_000_000..99_999_999)}")
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: user)
    create_incoming_message(conversation: conversation)
    conversation.messages.incoming.last.update!(content: transcript_line)
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    pipeline.update!(metadata: pipeline_metadata) if pipeline_metadata.present?
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, inbox: inbox, contact: contact,
                                     primary_conversation: conversation, title: 'Lead')
    account.crm_follow_ups.create!(
      card: card, conversation: conversation, contact: contact, title: 'Retomar', due_at: 10.minutes.ago,
      timezone: 'UTC', automation_mode: :auto_send_message, created_by: user, assignee: user, metadata: metadata
    )
  end

  def stub_credential
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(
      instance_double(Crm::Ai::CredentialResolver,
                      resolve: { api_key: 'sk-test', api_base: 'https://api.openai.com', source: :system })
    )
  end

  def stub_composition(&)
    composer = instance_double(Crm::Ai::FollowUpComposer)
    allow(Crm::Ai::FollowUpComposer).to receive(:new).and_return(composer)
    allow(composer).to receive(:perform, &)
  end

  def sendable_composition
    { 'should_send' => true, 'closure_detected' => false, 'confidence' => 0.9,
      'next_action_owner' => 'terceiro', 'message_kind' => 'aviso_andamento',
      'open_loop' => 'Orçamento prometido', 'open_loop_source' => transcript_line,
      'message_body' => 'Ainda estou com a seguradora.' }
  end

  describe Crm::FollowUps::MessageSender do
    it 'não cria mensagem quando o contato recusou e devolve opted_out' do
      follow_up = build_follow_up(metadata: { message_body: 'Olá' })
      follow_up.conversation.contact.opt_out!(source: 'manual')

      result = described_class.new(follow_up: follow_up).perform

      expect(result.status).to eq(:opted_out)
      expect(result.error).to eq('opt_out')
      expect(follow_up.conversation.messages.outgoing.count).to eq(0)
      expect(follow_up.reload.metadata['sent_message_id']).to be_nil
    end

    it 'envia normalmente quando o contato não recusou' do
      follow_up = build_follow_up(metadata: { message_body: 'Olá' })

      expect(described_class.new(follow_up: follow_up).perform.status).to eq(:sent)
    end
  end

  describe 'envio automático simples (DueProcessor)' do
    it 'cancela o follow-up com o motivo, sem enviar nem avisar falha' do
      follow_up = build_follow_up(metadata: { message_body: 'Olá' })
      follow_up.conversation.contact.opt_out!(source: 'prospecting')
      allow(ActionCableBroadcastJob).to receive(:perform_later)

      Crm::FollowUps::DueProcessor.new(now: Time.current).perform

      follow_up.reload
      expect(follow_up).to be_canceled
      expect(follow_up.metadata['canceled_reason']).to eq('opt_out')
      expect(follow_up.metadata['send_error']).to be_nil
      expect(follow_up.conversation.messages.outgoing.count).to eq(0)
      expect(follow_up.card.activities.where(event_type: 'follow_up_message_failed')).not_to exist
      expect(ActionCableBroadcastJob).not_to have_received(:perform_later)
        .with(anything, Events::Types::CRM_FOLLOW_UP_DUE, anything)
    end
  end

  describe Crm::FollowUps::CallbackRunner do
    let(:callback_metadata) do
      { 'source' => 'ai_callback', 'message_body' => '...', 'requested_at_text' => 'na terça', 'callback_retries' => 0 }
    end

    it 'vira lembrete humano sem chamar a IA quando o contato já recusou' do
      follow_up = build_follow_up(metadata: callback_metadata)
      follow_up.conversation.contact.opt_out!(source: 'manual')
      expect(Crm::Ai::FollowUpComposer).not_to receive(:new)

      result = described_class.new(follow_up: follow_up, now: Time.current).perform

      expect(result.status).to eq(:fallback)
      expect(result.error).to eq('opt_out')
    end

    it 'vira lembrete humano quando o contato recusa enquanto a IA compõe' do
      follow_up = build_follow_up(metadata: callback_metadata)
      stub_credential
      stub_composition do
        follow_up.conversation.contact.opt_out!(source: 'manual')
        sendable_composition
      end

      result = described_class.new(follow_up: follow_up, now: Time.current).perform

      expect(result.status).to eq(:fallback)
      expect(result.error).to eq('opt_out')
      expect(follow_up.conversation.messages.outgoing.count).to eq(0)
    end
  end

  describe Crm::FollowUps::AutoFollowupRunner do
    let(:ai_metadata) { { source: 'ai_followup', touch: 1, message_body: 'Olá' } }
    let(:pipeline_metadata) { { ai: { auto_followup: { enabled: true } } } }

    it 'para a cadência com motivo opt_out sem chamar a IA' do
      follow_up = build_follow_up(metadata: ai_metadata, pipeline_metadata: pipeline_metadata)
      follow_up.conversation.contact.opt_out!(source: 'manual')
      expect(Crm::Ai::FollowUpComposer).not_to receive(:new)

      result = described_class.new(follow_up: follow_up, now: Time.current).perform

      expect(result.status).to eq(:stopped)
      expect(follow_up.card.reload.metadata.dig('ai', 'auto_followup_state', 'stopped_reason')).to eq('opt_out')
    end

    it 'para a cadência quando o contato recusa enquanto a IA compõe, sem enviar' do
      follow_up = build_follow_up(metadata: ai_metadata, pipeline_metadata: pipeline_metadata)
      stub_credential
      stub_composition do
        follow_up.conversation.contact.opt_out!(source: 'email_unsubscribe')
        sendable_composition
      end

      result = described_class.new(follow_up: follow_up, now: Time.current).perform

      expect(result.status).to eq(:stopped)
      expect(follow_up.card.reload.metadata.dig('ai', 'auto_followup_state', 'stopped_reason')).to eq('opt_out')
      expect(follow_up.conversation.messages.outgoing.count).to eq(0)
    end

    it 'para a cadência quando a guarda do envio encontra a recusa' do
      follow_up = build_follow_up(metadata: ai_metadata, pipeline_metadata: pipeline_metadata)
      stub_credential
      stub_composition { sendable_composition }
      allow(Crm::FollowUps::MessageSender).to receive(:new).and_return(
        instance_double(Crm::FollowUps::MessageSender, perform: Crm::FollowUps::MessageSender::Result.opted_out)
      )

      result = described_class.new(follow_up: follow_up, now: Time.current).perform

      expect(result.status).to eq(:stopped)
      expect(follow_up.card.reload.metadata.dig('ai', 'auto_followup_state', 'stopped_reason')).to eq('opt_out')
    end
  end
end

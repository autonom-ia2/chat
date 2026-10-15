require 'rails_helper'

# #1638: o WhatsApp Híbrido (#1489) troca o aviso "mensagem não suportada" pelo texto real e publica
# `whatsapp_hybrid.message_recovered`. Mensagem do cliente com a IA de assunto ligada volta para a pergunta do assunto.
RSpec.describe Crm::Subjects::MensagemRecuperada do
  let(:account) { create_account_and_user.first }
  let(:inbox) { create_crm_inbox(account: account) }
  let(:contact) { account.contacts.create!(name: 'Recuperada', phone_number: '+5511987654321') }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }

  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run }
  end

  before { allow(Crm::Ai::Config).to receive(:enabled?).and_return(true) }

  def ligar(mode)
    account.crm_inbox_settings.find_or_initialize_by(inbox: inbox).update!(crm_enabled: true, subject_ai_mode: mode)
  end

  def criar_mensagem(message_type: :incoming, sender: contact)
    conversation.messages.create!(account: account, inbox: inbox, sender: sender, content: 'Texto real', message_type: message_type)
  end

  def publicar(message_id:, conversation_id: conversation.id, account_id: account.id)
    ActiveSupport::Notifications.instrument(
      'whatsapp_hybrid.message_recovered',
      message_id: message_id, conversation_id: conversation_id, account_id: account_id
    )
  end

  it 'reenfileira a pergunta do assunto uma vez, com a espera de sempre, para a mensagem do cliente' do
    ligar(:auto)
    message = criar_mensagem
    clear_enqueued_jobs

    freeze_time do
      publicar(message_id: message.id)

      expect(Crm::Subjects::IdentifyJob).to have_been_enqueued
        .with(conversation.id, message.id).at(Crm::Subjects::DEBOUNCE.from_now).exactly(:once)
    end
  end

  it 'não faz nada pela mensagem de saída' do
    ligar(:auto)
    message = criar_mensagem(message_type: :outgoing, sender: create(:user, account: account))
    clear_enqueued_jobs

    publicar(message_id: message.id)

    expect(Crm::Subjects::IdentifyJob).not_to have_been_enqueued
  end

  it 'não faz nada com a IA de assunto desligada na caixa' do
    ligar(:off)
    message = criar_mensagem
    clear_enqueued_jobs

    publicar(message_id: message.id)

    expect(Crm::Subjects::IdentifyJob).not_to have_been_enqueued
  end

  it 'não faz nada com o CRM desligado na instalação' do
    ligar(:auto)
    message = criar_mensagem
    clear_enqueued_jobs

    with_modified_env(CRM_KANBAN_ENABLED: 'false') { publicar(message_id: message.id) }

    expect(Crm::Subjects::IdentifyJob).not_to have_been_enqueued
  end

  it 'não faz nada quando a mensagem não existe' do
    ligar(:auto)
    clear_enqueued_jobs

    publicar(message_id: 0)

    expect(Crm::Subjects::IdentifyJob).not_to have_been_enqueued
  end

  it 'não faz nada quando a conversa ou a conta do evento não são as da mensagem' do
    ligar(:auto)
    message = criar_mensagem
    outra_conta = create_account_and_user.first
    clear_enqueued_jobs

    publicar(message_id: message.id, conversation_id: 0)
    publicar(message_id: message.id, account_id: outra_conta.id)

    expect(Crm::Subjects::IdentifyJob).not_to have_been_enqueued
  end

  it 'não faz nada pela nota privada' do
    ligar(:auto)
    message = conversation.messages.create!(account: account, inbox: inbox, sender: contact, content: 'Nota',
                                            message_type: :incoming, private: true)
    clear_enqueued_jobs

    publicar(message_id: message.id)

    expect(Crm::Subjects::IdentifyJob).not_to have_been_enqueued
  end

  it 'aceita o payload com chaves em texto' do
    ligar(:auto)
    message = criar_mensagem
    clear_enqueued_jobs

    ActiveSupport::Notifications.instrument(
      'whatsapp_hybrid.message_recovered',
      'message_id' => message.id, 'conversation_id' => conversation.id, 'account_id' => account.id
    )

    expect(Crm::Subjects::IdentifyJob).to have_been_enqueued.with(conversation.id, message.id).exactly(:once)
  end

  it 'não derruba quem publicou quando o enfileiramento falha, e o log leva só ids e classe' do
    ligar(:auto)
    message = criar_mensagem
    allow(Crm::Subjects::IdentifyJob).to receive(:set).and_raise(ArgumentError, 'segredo')
    allow(Rails.logger).to receive(:error)

    expect { publicar(message_id: message.id) }.not_to raise_error
    expect(Rails.logger).to have_received(:error)
      .with(include("message_id=#{message.id}", 'ArgumentError')).once
    expect(Rails.logger).not_to have_received(:error).with(include('segredo'))
  end
end

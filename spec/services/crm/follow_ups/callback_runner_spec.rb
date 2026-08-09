require 'rails_helper'

RSpec.describe Crm::FollowUps::CallbackRunner do
  # waha: true => WAHA (sem janela de 24h) => send_mode free_form.
  # waha: false + last_inbound_ago fora da janela de 24h => send_mode choose_template.
  def setup_card(account:, user:, waha: true, last_inbound_ago: nil)
    inbox = create_crm_whatsapp_api_inbox(account: account, members: [user])
    inbox.channel.enable_whatsapp_api_campaigns!(provider: 'cloud') unless waha
    contact = account.contacts.create!(name: 'Lead', phone_number: "+55119#{rand(10_000_000..99_999_999)}")
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: user)
    create_incoming_message(conversation: conversation)
    conversation.messages.incoming.last.update!(created_at: last_inbound_ago) if last_inbound_ago
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    card = account.crm_cards.create!(
      pipeline: pipeline, stage: stage, inbox: inbox, contact: contact,
      primary_conversation: conversation, title: 'Lead'
    )
    [card, conversation]
  end

  def build_callback_follow_up(account:, card:, conversation:, retries: 0)
    account.crm_follow_ups.create!(
      card: card, conversation: conversation, contact: card.contact, title: 'Retorno agendado',
      due_at: 10.minutes.ago, timezone: 'UTC', automation_mode: :auto_send_message,
      metadata: { 'source' => 'ai_callback', 'message_body' => '...', 'requested_at_text' => 'na próxima terça às 8h',
                  'callback_retries' => retries }
    )
  end

  def stub_credential
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(
      instance_double(Crm::Ai::CredentialResolver,
                      resolve: { api_key: 'sk-test', api_base: 'https://api.openai.com', source: :system })
    )
  end

  def stub_missing_credential
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(
      instance_double(Crm::Ai::CredentialResolver, resolve: nil)
    )
  end

  def stub_composition(payload)
    allow(Crm::Ai::FollowUpComposer).to receive(:new)
      .and_return(instance_double(Crm::Ai::FollowUpComposer, perform: payload))
  end

  it 'closure_detected na composição vira Result.fallback("closure") e nada é enviado' do
    account, user = create_account_and_user
    card, conversation = setup_card(account: account, user: user)
    follow_up = build_callback_follow_up(account: account, card: card, conversation: conversation)
    stub_credential
    stub_composition('should_send' => true, 'closure_detected' => true, 'confidence' => 0.9)
    expect(Crm::FollowUps::MessageSender).not_to receive(:new)

    result = described_class.new(follow_up: follow_up, now: Time.current).perform

    expect(result.status).to eq(:fallback)
    expect(result.error).to eq('closure')
  end

  it 'should_send false vira :fallback e nada é enviado' do
    account, user = create_account_and_user
    card, conversation = setup_card(account: account, user: user)
    follow_up = build_callback_follow_up(account: account, card: card, conversation: conversation)
    stub_credential
    stub_composition('should_send' => false, 'closure_detected' => false, 'confidence' => 0.9)
    expect(Crm::FollowUps::MessageSender).not_to receive(:new)

    result = described_class.new(follow_up: follow_up, now: Time.current).perform

    expect(result.status).to eq(:fallback)
  end

  # Confiança abaixo do piso (Crm::Ai::Config::FOLLOWUP_MIN_CONFIDENCE) é tratada como não-composável,
  # igual a should_send=false — a IA "quis" mandar mas sem convicção suficiente para produção.
  it 'confidence abaixo do piso mínimo vira :fallback e nada é enviado' do
    account, user = create_account_and_user
    card, conversation = setup_card(account: account, user: user)
    follow_up = build_callback_follow_up(account: account, card: card, conversation: conversation)
    stub_credential
    stub_composition('should_send' => true, 'closure_detected' => false,
                     'confidence' => Crm::Ai::Config::FOLLOWUP_MIN_CONFIDENCE - 0.01, 'message_body' => 'Oi')
    expect(Crm::FollowUps::MessageSender).not_to receive(:new)

    result = described_class.new(follow_up: follow_up, now: Time.current).perform

    expect(result.status).to eq(:fallback)
  end

  it 'caminho feliz free_form grava message_body no metadata e devolve :sent' do
    account, user = create_account_and_user
    card, conversation = setup_card(account: account, user: user)
    follow_up = build_callback_follow_up(account: account, card: card, conversation: conversation)
    stub_credential
    stub_composition('should_send' => true, 'closure_detected' => false, 'confidence' => 0.9,
                     'message_body' => 'Olá! Passando para retomar nosso papo.')
    allow(Crm::FollowUps::MessageSender).to receive(:new).and_return(
      instance_double(Crm::FollowUps::MessageSender, perform: Crm::FollowUps::MessageSender::Result.sent(nil))
    )

    result = described_class.new(follow_up: follow_up, now: Time.current).perform

    expect(result.status).to eq(:sent)
    expect(follow_up.reload.metadata['message_body']).to eq('Olá! Passando para retomar nosso papo.')
  end

  # Fail closed: credencial ausente precisa virar transiente tratado (Result :failed com retry_at),
  # nunca um NoMethodError cru vindo de dentro do ResponsesClient (@credential[:api_key]).
  it 'credencial ausente NÃO estoura NoMethodError e vira :failed com retry_at, incrementando callback_retries' do
    account, user = create_account_and_user
    card, conversation = setup_card(account: account, user: user)
    follow_up = build_callback_follow_up(account: account, card: card, conversation: conversation)
    stub_missing_credential

    result = nil
    expect { result = described_class.new(follow_up: follow_up, now: Time.current).perform }.not_to raise_error

    expect(result.status).to eq(:failed)
    expect(result.retry_at).to be_present
    expect(follow_up.reload.metadata['callback_retries']).to eq(1)
  end

  # Orçamento de tentativas com teto: no MAX_RETRIES o runner desiste do envio via IA e devolve
  # :fallback (vira lembrete pro humano) em vez de retransmitir infinitamente.
  it 'estourado MAX_RETRIES vira :fallback com motivo send_failed_N' do
    account, user = create_account_and_user
    card, conversation = setup_card(account: account, user: user)
    follow_up = build_callback_follow_up(account: account, card: card, conversation: conversation,
                                         retries: described_class::MAX_RETRIES - 1)
    stub_missing_credential

    result = described_class.new(follow_up: follow_up, now: Time.current).perform

    expect(result.status).to eq(:fallback)
    expect(result.error).to eq("send_failed_#{described_class::MAX_RETRIES}")
    expect(follow_up.reload.metadata['callback_retries']).to eq(described_class::MAX_RETRIES)
  end

  # --- Ataque: shapes adversariais da composição da IA -------------------------------------

  # composition nil (composer não devolveu nada, ex.: resposta vazia/parse falhou de um jeito que
  # não estourou exceção): closure?(nil) e composable?(nil) precisam tratar isso como "não compõe",
  # não como NoMethodError em composition['closure_detected'].
  it 'composition nil vira :fallback sem estourar exceção' do
    account, user = create_account_and_user
    card, conversation = setup_card(account: account, user: user)
    follow_up = build_callback_follow_up(account: account, card: card, conversation: conversation)
    stub_credential
    stub_composition(nil)
    expect(Crm::FollowUps::MessageSender).not_to receive(:new)

    result = nil
    expect { result = described_class.new(follow_up: follow_up, now: Time.current).perform }.not_to raise_error

    expect(result.status).to eq(:fallback)
    expect(result.error).to eq('not_composable')
  end

  # confidence AUSENTE do payload (não é 0.0 explícito, a chave simplesmente não existe):
  # composition['confidence'] é nil, .to_f vira 0.0, cai abaixo do piso mínimo -> fecha em
  # :fallback igual a confidence explicitamente baixa. Fail-closed correto, sem exceção.
  it 'confidence AUSENTE do payload (chave não existe) vira :fallback, não NoMethodError' do
    account, user = create_account_and_user
    card, conversation = setup_card(account: account, user: user)
    follow_up = build_callback_follow_up(account: account, card: card, conversation: conversation)
    stub_credential
    stub_composition('should_send' => true, 'closure_detected' => false, 'message_body' => 'Oi')
    expect(Crm::FollowUps::MessageSender).not_to receive(:new)

    result = nil
    expect { result = described_class.new(follow_up: follow_up, now: Time.current).perform }.not_to raise_error

    expect(result.status).to eq(:fallback)
  end

  # Fora da janela de 24h o runner entra em :choose_template; sem candidato válido (index -1, a IA
  # não achou template adequado) precisa virar lembrete, não um envio quebrado.
  it 'modo choose_template sem candidato válido (index -1) vira :fallback("no_template")' do
    account, user = create_account_and_user
    card, conversation = setup_card(account: account, user: user, waha: false, last_inbound_ago: 30.hours.ago)
    follow_up = build_callback_follow_up(account: account, card: card, conversation: conversation)
    stub_credential
    stub_composition('should_send' => true, 'closure_detected' => false, 'confidence' => 0.9,
                     'message_body' => 'Oi', 'chosen_template' => { 'index' => -1 })
    expect(Crm::FollowUps::MessageSender).not_to receive(:new)

    result = described_class.new(follow_up: follow_up, now: Time.current).perform

    expect(result.status).to eq(:fallback)
    expect(result.error).to eq('no_template')
  end
end

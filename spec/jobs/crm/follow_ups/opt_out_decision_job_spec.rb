require 'rails_helper'

# Decisão de opt-out pelo modelo (#1317). O modelo é simulado (sem chamada paga): o spec prova o que o card grava para
# cada resposta do modelo — pedido claro, mensagem ambígua, mensagem sem relação — e que falha do provedor e falta de
# chave ficam visíveis, sem virar opt-out nem sumir.
RSpec.describe Crm::FollowUps::OptOutDecisionJob do
  let(:account) { create(:account) }
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:card) { create_card }
  let(:conversation) { card.primary_conversation }

  around { |example| with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_AI_ENABLED' => 'true') { example.run } }

  before do
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k' }))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
  end

  def create_card
    user = create(:user, account: account)
    inbox = create_crm_inbox(account: account, members: [user])
    contact = account.contacts.create!(name: 'Lead', phone_number: "+55119#{rand(10_000_000..99_999_999)}")
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: user)
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    account.crm_cards.create!(pipeline: pipeline, stage: stage, inbox: inbox, contact: contact,
                              primary_conversation: conversation, title: 'Lead',
                              metadata: { 'ai' => { 'auto_followup_state' => { 'active' => true } } })
  end

  # A resposta passa pelo canceler de verdade: é ele que deixa o estado "pendente" que o job confere.
  def reply(content)
    conversation.messages.create!(account_id: account.id, inbox_id: conversation.inbox_id, message_type: :outgoing,
                                  content: 'Oi! Ainda tem interesse no orçamento?')
    message = create_incoming_message(conversation: conversation, content: content)
    Crm::FollowUps::AutoFollowupCanceler.new(card: card, message: message).maybe_cancel
    message
  end

  def model_answers(decision, motivo)
    allow(client).to receive(:create).and_return(text: { pediu_para_parar: decision, motivo: motivo }.to_json)
  end

  def state
    card.reload.metadata['ai']['auto_followup_state']
  end

  it 'pedido claro de parar: marca opted_out, registra a atividade e loga sem o texto da mensagem' do
    message = reply('Por favor, parem de me mandar essas mensagens')
    model_answers('sim', 'pedido_explicito_de_parar')
    allow(Rails.logger).to receive(:info)

    described_class.perform_now(card.id, message.id)

    expect(state).to include('opted_out' => true, 'stopped_reason' => 'opt_out', 'opt_out_decision' => 'sim',
                             'opt_out_motivo' => 'pedido_explicito_de_parar')
    activity = card.activities.where(event_type: 'ai_followup_stopped').find_by("payload->>'trigger' = 'opt_out_decision'")
    expect(activity.payload).to include('reason' => 'opt_out', 'message_id' => message.id, 'motivo' => 'pedido_explicito_de_parar')
    expect(Rails.logger).to have_received(:info)
      .with("[crm][ai][opt_out] card_id=#{card.id} message_id=#{message.id} decisao=sim motivo=pedido_explicito_de_parar")
    expect(client).to have_received(:create) do |args|
      expect(JSON.parse(args[:input])).to eq('reply' => 'Por favor, parem de me mandar essas mensagens',
                                             'previous_message' => 'Oi! Ainda tem interesse no orçamento?')
      expect(args[:schema][:schema][:properties][:pediu_para_parar][:enum]).to eq(%w[sim nao nao_se_aplica])
      expect(args[:timeout]).to eq(Crm::Ai::OptOutClassifier::TIMEOUT)
    end
  end

  describe 'recusa no contato (chat#1325)' do
    let(:contact) { conversation.contact }

    it '"sim" também grava a recusa no contato, com a origem follow_up_reply' do
      message = reply('Não quero mais receber, obrigado')
      model_answers('sim', 'pedido_explicito_de_parar')

      described_class.perform_now(card.id, message.id)

      contact.reload
      expect(contact).to be_opted_out
      expect(contact.opt_out_source).to eq('follow_up_reply')
      expect(contact.opted_out_by_id).to be_nil
      expect(state[Crm::FollowUps::CardOptOut::CONTACT_KEY]).to eq(contact.id)
    end

    it '"sim" não troca a recusa que o contato já tinha por outra origem' do
      user = create(:user, account: account)
      contact.opt_out!(source: 'manual', by: user)
      refused_at = contact.reload.opted_out_at
      message = reply('Parem de mandar mensagem')
      model_answers('sim', 'pedido_explicito_de_parar')

      described_class.perform_now(card.id, message.id)

      contact.reload
      expect(contact.opt_out_source).to eq('manual')
      expect(contact.opted_out_by_id).to eq(user.id)
      expect(contact.opted_out_at).to eq(refused_at)
      expect(state).to include('opted_out' => true)
    end

    it '"nao" não marca o contato' do
      message = reply('agora não dá, depois a gente vê')
      model_answers('nao', 'ambigua')

      described_class.perform_now(card.id, message.id)

      expect(contact.reload).not_to be_opted_out
    end

    it 'erro de banco ao gravar o contato desfaz o card junto, tenta de novo sem chamar o modelo de novo e, esgotado, grava "falhou"' do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      message = reply('SAIR')
      model_answers('sim', 'pedido_explicito_de_parar')
      attempts = 0
      allow_any_instance_of(Contact).to receive(:opt_out!) do # rubocop:disable RSpec/AnyInstance
        attempts += 1
        raise ActiveRecord::RecordNotSaved
      end
      allow(Rails.logger).to receive(:error)

      perform_enqueued_jobs(only: described_class) { described_class.perform_later(card.id, message.id) }

      expect(client).to have_received(:create).once
      expect(attempts).to eq(5)
      expect(state).to include('opted_out' => false, 'opt_out_decision' => 'falhou', 'opt_out_motivo' => 'ActiveRecord::RecordNotSaved')
      expect(card.activities.where(event_type: 'ai_followup_stopped').where("payload->>'trigger' = 'opt_out_decision'")).to be_empty
      expect(contact.reload).not_to be_opted_out
      expect(Rails.logger).to have_received(:error)
        .with("[crm][ai][opt_out] card_id=#{card.id} message_id=#{message.id} decisao=falhou erro=ActiveRecord::RecordNotSaved")
    end

    it 'com card.contact diferente do contato da conversa, marca o da conversa, o mesmo a quem o follow-up escreve' do
      other = account.contacts.create!(name: 'Outro', phone_number: "+55118#{rand(10_000_000..99_999_999)}")
      card.update!(contact: other)
      message = reply('SAIR')
      model_answers('sim', 'pedido_explicito_de_parar')

      described_class.perform_now(card.id, message.id)

      card.reload
      expect(Crm::FollowUps::CardOptOut.contact_for(card)).to eq(contact)
      expect(state[Crm::FollowUps::CardOptOut::CONTACT_KEY]).to eq(contact.id)
      expect(contact.reload.opt_out_source).to eq('follow_up_reply')
      expect(other.reload).not_to be_opted_out
      expect(Crm::FollowUps::CardOptOut.contact_marked?(other)).to be(false)
    end
  end

  it 'nota privada do time não vai ao modelo como contexto' do
    conversation.messages.create!(account_id: account.id, inbox_id: conversation.inbox_id, message_type: :outgoing,
                                  content: 'Oi! Ainda tem interesse no orçamento?')
    conversation.messages.create!(account_id: account.id, inbox_id: conversation.inbox_id, message_type: :outgoing,
                                  private: true, content: 'nota interna sobre o cliente')
    message = create_incoming_message(conversation: conversation, content: 'SAIR')
    Crm::FollowUps::AutoFollowupCanceler.new(card: card, message: message).maybe_cancel
    model_answers('sim', 'pedido_explicito_de_parar')

    described_class.perform_now(card.id, message.id)

    expect(client).to have_received(:create) do |args|
      expect(JSON.parse(args[:input])['previous_message']).to eq('Oi! Ainda tem interesse no orçamento?')
    end
  end

  it 'mensagem ambígua: o modelo diz "nao" e o card fica como resposta comum' do
    message = reply('agora não dá, depois a gente vê')
    model_answers('nao', 'ambigua')

    described_class.perform_now(card.id, message.id)

    expect(state).to include('opted_out' => false, 'stopped_reason' => 'replied', 'opt_out_decision' => 'nao', 'opt_out_motivo' => 'ambigua')
    expect(card.activities.where(event_type: 'ai_followup_stopped').count).to eq(1)
  end

  it 'mensagem sem relação com parar: o modelo diz "nao" e nada vira opt-out' do
    message = reply('vou sair agora, te respondo depois')
    model_answers('nao', 'resposta_ao_assunto')

    described_class.perform_now(card.id, message.id)

    expect(state).to include('opted_out' => false, 'stopped_reason' => 'replied', 'opt_out_decision' => 'nao')
  end

  it 'sem texto para interpretar: grava nao_se_aplica sem chamar o modelo' do
    message = reply('')

    described_class.perform_now(card.id, message.id)

    expect(state).to include('opted_out' => false, 'opt_out_decision' => 'nao_se_aplica', 'opt_out_motivo' => 'sem_texto_interpretavel')
    expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
  end

  it 'falha do provedor: tenta de novo e, esgotado, grava "falhou" e loga o erro, sem marcar opt-out' do
    message = reply('SAIR')
    allow(client).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'network_timeout: read_timeout')
    allow(Rails.logger).to receive(:error)

    perform_enqueued_jobs(only: described_class) { described_class.perform_later(card.id, message.id) }

    expect(client).to have_received(:create).exactly(5).times
    expect(state).to include('opted_out' => false, 'stopped_reason' => 'replied', 'opt_out_decision' => 'falhou',
                             'opt_out_motivo' => 'Crm::Ai::ResponsesClient::Error')
    expect(Rails.logger).to have_received(:error)
      .with("[crm][ai][opt_out] card_id=#{card.id} message_id=#{message.id} decisao=falhou erro=Crm::Ai::ResponsesClient::Error")
  end

  it 'resposta do modelo fora do schema conta como falha, não como decisão' do
    message = reply('SAIR')
    allow(client).to receive(:create).and_return(text: { pediu_para_parar: 'talvez', motivo: 'ambigua' }.to_json)

    perform_enqueued_jobs(only: described_class) { described_class.perform_later(card.id, message.id) }

    expect(state).to include('opted_out' => false, 'opt_out_decision' => 'falhou', 'opt_out_motivo' => 'Crm::Ai::OptOutClassifier::InvalidAnswer')
  end

  it 'conta sem chave de IA: grava sem_credencial na hora, sem tentar de novo' do
    message = reply('SAIR')
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: nil))

    perform_enqueued_jobs(only: described_class) { described_class.perform_later(card.id, message.id) }

    expect(state).to include('opted_out' => false, 'opt_out_decision' => 'sem_credencial')
    expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
  end

  it 'estado mudou antes da decisão (reset manual): não chama o modelo nem sobrescreve nada' do
    message = reply('SAIR')
    card.update!(metadata: { 'ai' => { 'auto_followup_state' => { 'active' => false, 'opted_out' => false } } })

    described_class.perform_now(card.id, message.id)

    expect(state).to eq('active' => false, 'opted_out' => false)
    expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
  end
end

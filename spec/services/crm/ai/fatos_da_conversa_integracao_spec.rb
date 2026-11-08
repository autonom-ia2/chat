require 'rails_helper'

# IA entende a conversa F1, de ponta a ponta (sem chamar IA de verdade): o nosso agente promete uma pessoa ao cliente, a
# fala dele agenda a avaliação do card em foco, a avaliação roda 2 min depois com a ordem da conversa e o schema da
# promessa, e a passagem é cumprida pela Entrega. Sem a flag, a mesma conversa não agenda nada e nada muda.
RSpec.describe Crm::Ai::FatosDaConversa do
  include ActiveJob::TestHelper
  include_context 'with crm responsible agent'

  let(:pessoa) { create(:user, account: account) }
  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }
  let(:chamadas) { [] }
  let!(:card) do
    card = create_card(pipeline: comercial)
    card.stage.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r2_direct' } })
    card.reload
  end
  let(:resposta) do
    { suggested_stage_id: card.stage_id, confidence: 0.9, reasoning: 'Promessa do assistente sem pessoa', value: nil,
      handoff: { intent: 'transferir', should_handoff: true, reason: 'prometido', suggested_agent: nil, promised_by_our_assistant: true },
      callback_request: nil, extracted_attributes: { contact: [], conversation: [], card: [] }, score_signals: nil }
  end

  before do
    inbox.add_members([pessoa.id])
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return({ pessoa.id => 'online' })
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Cards::Broadcaster).to receive(:broadcast)
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: { api_key: 'k' }))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
    allow(cliente).to receive(:create) do |**args|
      chamadas << args
      { text: resposta.to_json, usage: {}, response_id: 'r' }
    end
    account.crm_inbox_settings.find_by!(inbox: inbox).update!(auto_create_card: false)
    account.enable_features!(Crm::Conversations::CardEmFoco::FLAG)
    clear_enqueued_jobs
  end

  def conversa_com_promessa
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'Preciso de ajuda',
                     sender: contact)
    fala = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                            content: 'Vou chamar uma pessoa da equipe para te atender', sender: porta)
    Crm::Conversations::CardSyncer.new(conversation: conversation.reload, message: fala).perform
  end

  def rodar_avaliacoes
    jobs = enqueued_jobs.select { |job| job['job_class'] == Crm::Ai::EvaluateCardJob.name }
    travel(Crm::Conversations::CardEmFoco::ESPERA_DA_EQUIPE + 1.second) do
      jobs.each { |job| Crm::Ai::EvaluateCardJob.perform_now(*job['arguments']) }
    end
    jobs
  end

  it 'com a flag: a fala do robô agenda, a avaliação lê a ordem e a promessa é cumprida', :aggregate_failures do
    account.enable_features!(described_class::FLAG)
    conversa_com_promessa

    expect(rodar_avaliacoes.map { |job| job['arguments'].last }).to eq([described_class::TRIGGER_DO_ROBO])
    expect(chamadas.size).to eq(1)
    enviado = chamadas.first
    entrada = JSON.parse(enviado[:input])
    expect(enviado[:instructions]).to end_with(described_class::ORDEM)
    expect(enviado[:schema][:schema][:properties][:handoff][:required]).to include('promised_by_our_assistant')
    mensagens = entrada['recent_messages']
    expect(mensagens.first).to include('role' => 'customer', 'after' => nil)
    expect(mensagens.last).to include('role' => 'platform_agent')
    expect(mensagens.last).not_to have_key('after')
    expect(entrada['conversation_state']).to include('customer_waiting_since' => nil)
    expect(conversation.reload.assignee_id).to eq(pessoa.id)
  end

  it 'sem a flag: a fala do robô não agenda nada e o agente segue com a conversa', :aggregate_failures do
    conversa_com_promessa

    expect(rodar_avaliacoes).to be_empty
    expect(chamadas).to be_empty
    expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: porta)
  end
end

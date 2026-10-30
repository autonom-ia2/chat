require 'rails_helper'

# #2018: a decisão grava o que o Jev respondeu e por que o modelo maior foi chamado. Só registro: a decisão é a mesma.
RSpec.describe Crm::Subjects::Identifier do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Joana Lima') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:comercial) { create_crm_pipeline(account: account, user: admin, name: 'Comercial').first }
  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }

  before do
    stage = comercial.stages.order(:position, :id).first
    account.crm_pipeline_inboxes.create!(pipeline: comercial, inbox: inbox, default_stage: stage, auto_create_card: true, created_by: admin)
    account.crm_inbox_settings.create!(inbox: inbox, crm_enabled: true, auto_create_card: true, subject_ai_mode: :auto)
    allow(TypesafeAi::Config).to receive_messages(configured?: true, api_key: 'ts_test_key_not_real', model: 'jev-1.13.0')
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k' }))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
    allow(cliente).to receive(:create)
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
  end

  def incoming(content)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: content)
  end

  def create_card(title:, focused_at: nil)
    card = account.crm_cards.create!(pipeline: comercial, stage: comercial.stages.order(:position, :id).first, contact: contact,
                                     primary_conversation: conversation, inbox: inbox, title: title)
    Crm::CardConversation.find_or_create_by!(account: account, card: card, conversation: conversation)
                         .update!(is_primary: true, focused_at: focused_at)
    card
  end

  def stub_jev(choice, confidence: 0.95)
    stub_request(:post, 'https://api.typesafe.ai/v1/systemone').to_return do
      body = { model: 'jev-1.13.0', usage: { input_tokens: 300, output_tokens: 5 },
               answers: { decisao: { type: 'choice', choice: choice, confidence: confidence } } }
      { status: 200, body: body.to_json }
    end
  end

  def stub_review(resposta:, titulo: '', seguro: true)
    resposta_dos_dois = { resposta: resposta, titulo: titulo, seguro: seguro, motivo: 'ok',
                          assuntos: [{ resposta: resposta, titulo: titulo, seguro: seguro }], principal: 0 }
    allow(cliente).to receive(:create).and_return(text: resposta_dos_dois.to_json)
  end

  def identify(message)
    described_class.new(conversation: conversation, message: message).perform
  end

  it 'o Jev decide sozinho: grava a resposta dele e nenhum motivo de revisão' do
    agentes = create_card(title: 'Agentes de IA', focused_at: 2.hours.ago)
    create_card(title: 'Chat2You', focused_at: 1.hour.ago)
    stub_jev("card_#{agentes.id}")

    decision = identify(incoming('Voltando aos agentes'))

    expect(decision).to have_attributes(state: 'applied', action: 'focus', decided_by: 'jev', jev_answer: 'card', review_reason: nil)
    expect(cliente).not_to have_received(:create)
  end

  it 'certeza baixa: grava certeza_baixa, mesmo quando o Jev escolheu pedido novo (o primeiro gatilho vale)' do
    create_card(title: 'Agentes de IA', focused_at: 1.hour.ago)
    stub_jev("novo_#{comercial.id}", confidence: 0.4)
    stub_review(resposta: "novo_#{comercial.id}", titulo: 'Chat2You')

    decision = identify(incoming('E o Chat2You?'))

    expect(decision).to have_attributes(decided_by: 'review', jev_answer: 'novo', review_reason: 'certeza_baixa')
  end

  it 'pedido novo com o Jev seguro: grava pedido_novo' do
    create_card(title: 'Agentes de IA', focused_at: 1.hour.ago)
    stub_jev("novo_#{comercial.id}")
    stub_review(resposta: "novo_#{comercial.id}", titulo: 'Chat2You')

    decision = identify(incoming('E o Chat2You, quanto custa?'))

    expect(decision).to have_attributes(state: 'applied', action: 'create', decided_by: 'review', jev_answer: 'novo',
                                        review_reason: 'pedido_novo')
  end

  it 'o modelo maior corrige o Jev: a resposta original do Jev fica gravada, diferente da decisão final' do
    agentes = create_card(title: 'Agentes de IA', focused_at: 2.hours.ago)
    create_card(title: 'Chat2You', focused_at: 1.hour.ago)
    stub_jev('mesmo_assunto', confidence: 0.5)
    stub_review(resposta: "card_#{agentes.id}")

    decision = identify(incoming('Sobre os agentes, ainda tenho uma dúvida'))

    expect(decision).to have_attributes(state: 'applied', action: 'focus', card_id: agentes.id, decided_by: 'review',
                                        jev_answer: 'mesmo', review_reason: 'certeza_baixa')
  end

  it 'a dúvida do modelo maior também grava a resposta do Jev e o motivo' do
    create_card(title: 'Agentes de IA', focused_at: 1.hour.ago)
    stub_jev("novo_#{comercial.id}")
    stub_review(resposta: "novo_#{comercial.id}", titulo: 'Talvez outro', seguro: false)

    expect(identify(incoming('E aquilo outro?'))).to have_attributes(state: 'doubt', jev_answer: 'novo', review_reason: 'pedido_novo')
  end

  it 'resposta inválida do modelo maior vira falha e grava a resposta do Jev e o motivo' do
    create_card(title: 'Agentes de IA', focused_at: 1.hour.ago)
    stub_jev("novo_#{comercial.id}")
    stub_review(resposta: 'card_0', titulo: 'Chat2You')

    expect(identify(incoming('E o Chat2You?'))).to have_attributes(state: 'failed', reason: 'resposta_invalida', jev_answer: 'novo',
                                                                   review_reason: 'pedido_novo')
  end

  it 'sugestão repetida: o modelo maior não é chamado, a resposta do Jev fica e o motivo não' do
    create_card(title: 'Agentes de IA', focused_at: 1.hour.ago)
    Crm::SubjectDecision.create!(account: account, conversation: conversation, mode: 'suggest', action: 'create',
                                 state: 'suggested', pipeline: comercial)
    stub_jev("novo_#{comercial.id}")

    decision = identify(incoming('E o Chat2You?'))

    expect(decision).to have_attributes(state: 'kept', reason: 'sugestao_pendente', jev_answer: 'novo', review_reason: nil)
    expect(cliente).not_to have_received(:create)
  end

  it 'sem texto para ler: o Jev não é perguntado e nada é gravado' do
    expect(identify(incoming(nil))).to have_attributes(state: 'no_content', jev_answer: nil, review_reason: nil)
  end

  context 'with a flag de vários assuntos por mensagem (#1693)' do
    before do
      account.enable_features!(Crm::Conversations::CardEmFoco::FLAG)
      allow(Crm::Config).to receive(:enabled?).and_return(true)
      allow(Crm::Cards::Broadcaster).to receive(:broadcast)
    end

    it 'o Jev escolhe vários assuntos: grava varios' do
      create_card(title: 'Agentes de IA', focused_at: 1.hour.ago)
      stub_jev(Crm::Subjects::Question::VARIOS)
      stub_review(resposta: "novo_#{comercial.id}", titulo: 'Chat2You')

      decision = identify(incoming('Fechei os agentes. E o Chat2You?'))

      expect(decision).to have_attributes(decided_by: 'review', jev_answer: 'varios', review_reason: 'varios')
    end

    it '"o mesmo assunto" num card ainda sem nome: grava nome_do_atual (#1918)' do
      create_card(title: 'Joana Lima', focused_at: 1.hour.ago)
      stub_jev(Crm::Subjects::Question::MESMO_ASSUNTO)
      stub_review(resposta: "novo_#{comercial.id}", titulo: 'Agentes de IA')

      decision = identify(incoming('Queria saber dos agentes de IA'))

      expect(decision).to have_attributes(decided_by: 'review', jev_answer: 'mesmo', review_reason: 'nome_do_atual')
    end
  end
end

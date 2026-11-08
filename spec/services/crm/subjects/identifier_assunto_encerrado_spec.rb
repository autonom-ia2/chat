require 'rails_helper'

# IA entende a conversa F2 (flag `crm_ia_assunto_encerrado`), de ponta a ponta na IA de assunto, com o Jev e o modelo
# maior simulados: a mensagem sobre um assunto encerrado não cria, não foca, não reabre card e não faz a IA de etapa
# reler card nenhum (regra b). Sem a flag, a pergunta é a de sempre.
RSpec.describe Crm::Subjects::Identifier do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Pessoa Cliente') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin, name: 'Funil A') }
  let(:pipeline) { pipeline_and_stage.first }
  let(:first_stage) { pipeline_and_stage.last }
  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }
  let!(:aberto) { create_card(title: 'Pedido aberto', focused_at: 1.hour.ago) }
  let!(:fechado) { create_card(title: 'Pedido anterior', focused_at: 2.days.ago, status: :lost, fechado_ha: 2.days) }

  before do
    account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: first_stage, created_by: admin)
    account.crm_inbox_settings.create!(inbox: inbox, crm_enabled: true, subject_ai_mode: :auto)
    allow(TypesafeAi::Config).to receive_messages(configured?: true, api_key: 'ts_test_key_not_real', model: 'jev-1.13.0')
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k' }))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
    allow(cliente).to receive(:create)
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
  end

  def create_card(title:, focused_at:, status: :open, fechado_ha: nil)
    card = account.crm_cards.create!(pipeline: pipeline, stage: first_stage, contact: contact, primary_conversation: conversation,
                                     inbox: inbox, title: title, metadata: { 'subject' => { 'source' => 'ai' } })
    Crm::CardConversation.find_or_create_by!(account: account, card: card, conversation: conversation).update!(focused_at: focused_at)
    return card if status == :open

    card.update!(status: status)
    card.update_columns(closed_at: fechado_ha.ago) # rubocop:disable Rails/SkipsModelValidations
    card
  end

  def incoming(content)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: content)
  end

  def stub_jev(choice, confidence: 0.95)
    requests = []
    stub_request(:post, 'https://api.typesafe.ai/v1/systemone').to_return do |request|
      requests << request.body
      body = { model: 'jev-1.13.0', usage: { input_tokens: 300, output_tokens: 5 },
               answers: { decisao: { type: 'choice', choice: choice, confidence: confidence } } }
      { status: 200, body: body.to_json }
    end
    requests
  end

  def identify(message)
    described_class.new(conversation: conversation, message: message).perform
  end

  def foco = Crm::Assunto.funil_atual(conversation.reload)

  context 'with the flag on' do
    before { account.enable_features!(Crm::Subjects::Encerrado::FLAG) }

    context 'with several subjects per message (crm_avaliar_toda_mensagem)' do
      before { account.enable_features!(Crm::Conversations::CardEmFoco::FLAG) }

      it 'a mensagem só sobre o encerrado: nada muda e a IA de etapa não relê card nenhum', :aggregate_failures do
        requests = stub_jev("encerrado_#{fechado.id}")
        mensagem = incoming('Obrigada pelo que fizeram')

        decisao = identify(mensagem)

        expect(requests.join).to include("encerrado_#{fechado.id}", Crm::Subjects::Encerrado::INSTRUCAO.to_json[1, 60])
        expect(decisao).to have_attributes(state: 'kept', action: 'none', reason: Crm::Subjects::Encerrado::MOTIVO,
                                           card_id: fechado.id, touched_card_ids: [], decided_by: 'jev')
        expect(fechado.reload).to be_lost
        expect(account.crm_cards.count).to eq(2)
        expect(foco).to eq(aberto)
        expect { Crm::Conversations::CardsTocados.new(conversation: conversation, message: mensagem).perform }
          .not_to have_enqueued_job(Crm::Ai::EvaluateCardsJob)
      end

      it 'encerrado e pedido novo na mesma mensagem: só o pedido novo vira card; o encerrado fica fechado', :aggregate_failures do
        stub_jev(Crm::Subjects::Question::VARIOS)
        resposta = { assuntos: [{ resposta: "encerrado_#{fechado.id}", titulo: '', seguro: true },
                                { resposta: "novo_#{pipeline.id}", titulo: 'Pedido novo', seguro: true }], principal: 1, motivo: 'ok' }
        allow(cliente).to receive(:create).and_return(text: resposta.to_json)

        decisao = identify(incoming('Obrigada pelo anterior. Agora quero outra coisa'))
        novo = account.crm_cards.find_by!(title: 'Pedido novo')

        expect(decisao).to have_attributes(state: 'applied', action: 'create', card_id: novo.id, touched_card_ids: [novo.id])
        expect(fechado.reload).to be_lost
        expect(cliente).to have_received(:create).with(hash_including(
                                                         instructions: a_string_ending_with(Crm::Subjects::Encerrado::INSTRUCAO_DA_LISTA)
                                                       ))
      end
    end

    it 'sem vários assuntos: a decisão fica mantida no encerrado, com a lista de cards vazia', :aggregate_failures do
      stub_jev("encerrado_#{fechado.id}")

      decisao = identify(incoming('Deu tudo certo, obrigada'))

      expect(decisao).to have_attributes(state: 'kept', reason: Crm::Subjects::Encerrado::MOTIVO, card_id: fechado.id, touched_card_ids: [])
      expect(fechado.reload).to be_lost
      expect(foco).to eq(aberto)
    end

    it 'arquivado e fechado fora da janela não viram opção', :aggregate_failures do
      arquivado = create_card(title: 'Pedido arquivado', focused_at: 3.days.ago, status: :archived, fechado_ha: 1.day)
      antigo = create_card(title: 'Pedido antigo', focused_at: 4.days.ago, status: :won, fechado_ha: 100.days)
      requests = stub_jev('sem_assunto')

      identify(incoming('Oi'))

      expect(requests.join).to include("encerrado_#{fechado.id}")
      expect(requests.join).not_to include("encerrado_#{arquivado.id}", "encerrado_#{antigo.id}")
    end
  end

  it 'sem a flag, o encerrado não vira opção e as instruções são as de sempre', :aggregate_failures do
    requests = stub_jev('sem_assunto')

    identify(incoming('Obrigada pelo que fizeram'))

    expect(requests.join).not_to include('encerrado_')
    expect(described_class.new(conversation: conversation, message: incoming('x')).send(:question).instrucoes)
      .to eq(Crm::Subjects::Question::INSTRUCOES)
  end
end

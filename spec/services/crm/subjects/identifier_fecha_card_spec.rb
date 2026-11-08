require 'rails_helper'

# IA entende a conversa F3 (flag `crm_ia_fecha_card`): o respeito de 24 h ao fechamento (Crm::Subjects::Applier) é
# para o que uma PESSOA fechou. O card que a IA fechou (o "adiou", por exemplo) não segura o pedido novo do cliente que
# volta como só sugestão. Sem a flag, qualquer fechamento segura, como antes.
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

  before do
    account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: first_stage, auto_create_card: true, created_by: admin)
    account.crm_inbox_settings.create!(inbox: inbox, crm_enabled: true, auto_create_card: true, subject_ai_mode: :auto)
    allow(TypesafeAi::Config).to receive_messages(configured?: true, api_key: 'ts_test_key_not_real', model: 'jev-1.13.0')
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k' }))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
    resposta = { resposta: "novo_#{pipeline.id}", titulo: 'Pedido novo', seguro: true, motivo: 'ok',
                 assuntos: [{ resposta: "novo_#{pipeline.id}", titulo: 'Pedido novo', seguro: true }], principal: 0 }
    allow(cliente).to receive(:create).and_return(text: resposta.to_json)
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    stub_request(:post, 'https://api.typesafe.ai/v1/systemone').to_return(
      status: 200, body: { model: 'jev-1.13.0', usage: { input_tokens: 300, output_tokens: 5 },
                           answers: { decisao: { type: 'choice', choice: "novo_#{pipeline.id}", confidence: 0.95 } } }.to_json
    )
    create_card(title: 'Outro pedido', focused_at: 2.hours.ago)
  end

  def create_card(title:, focused_at:)
    card = account.crm_cards.create!(pipeline: pipeline, stage: first_stage, contact: contact, primary_conversation: conversation,
                                     inbox: inbox, title: title)
    Crm::CardConversation.find_or_create_by!(account: account, card: card, conversation: conversation).update!(focused_at: focused_at)
    card
  end

  def fechado(por:)
    card = create_card(title: 'Pedido fechado', focused_at: 1.hour.ago)
    extra = por.nil? ? { by: 'ai', motivo: 'adiou' } : {}
    Crm::Cards::Closer.new(card: card, actor: por, result: 'lost', payload_extra: extra).perform
    card
  end

  def identify
    message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'Quero outra coisa')
    described_class.new(conversation: conversation, message: message).perform
  end

  context 'with the flag on' do
    before { account.enable_features!(Crm::Ai::FecharCard::FLAG) }

    # Pega: o "adiou" da IA virar trava, e o cliente que volta com pedido novo ganhar só uma sugestão. Legado: desde o
    # #2389 a IA não fecha mais card; o caso cobre os fechamentos de antes do deploy, nas 24 h seguintes.
    it 'card fechado pela IA há pouco (legado, antes do #2389): o pedido novo vira card' do
      fechado(por: nil)

      expect { identify }.to change(Crm::Card, :count).by(1)
    end

    it 'card fechado por uma pessoa há pouco: o pedido novo segue sugestão' do
      fechado(por: admin)

      expect { identify }.not_to change(Crm::Card, :count)
      expect(Crm::SubjectDecision.last).to have_attributes(action: 'create', state: 'suggested')
    end
  end

  it 'sem a flag: o card fechado pela IA também segura (como antes)' do
    fechado(por: nil)

    expect { identify }.not_to change(Crm::Card, :count)
    expect(Crm::SubjectDecision.last).to have_attributes(action: 'create', state: 'suggested')
  end
end

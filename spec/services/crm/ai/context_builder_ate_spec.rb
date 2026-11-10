require 'rails_helper'

# #1920: com `ate`, o contexto é o do card naquele instante. Mensagem posterior, conversa ligada depois, envio que falhou
# e a etapa de agora ficam de fora.
RSpec.describe Crm::Ai::ContextBuilder do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline) { create_crm_pipeline(account: account, user: admin).first }
  let(:inbox) { create_crm_inbox(account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let(:card) do
    account.crm_cards.create!(pipeline: pipeline, stage: pipeline.stages.first, title: 'Pedido', contact: contact,
                              primary_conversation: conversation, currency: 'BRL')
  end
  let(:decisao) { 1.hour.ago }

  def falar(texto, momento, conversa: conversation, **atributos)
    travel_to(momento) do
      create(:message, account: account, inbox: inbox, conversation: conversa, content: texto, message_type: :incoming, sender: contact,
                       **atributos)
    end
  end

  def ligar(outra, momento)
    travel_to(momento) { Crm::CardConversation.create!(account: account, card: card, conversation: outra) }
  end

  def textos(contexto) = contexto[:recent_messages].pluck(:content)

  it 'lê só as mensagens até o instante e não traz a etapa de agora', :aggregate_failures do
    falar('quero cotar', decisao - 5.minutes)
    falar('fechei com outra', decisao + 5.minutes)

    contexto = described_class.new(card: card, ate: decisao).perform

    expect(textos(contexto)).to eq(['quero cotar'])
    expect(contexto).not_to have_key(:current_stage)
  end

  it 'deixa de fora a conversa ligada ao card depois do instante, mesmo com mensagens de antes' do
    antes = create_crm_conversation(account: account, inbox: inbox, contact: contact)
    depois = create_crm_conversation(account: account, inbox: inbox, contact: contact)
    falar('pela outra conversa', decisao - 10.minutes, conversa: antes)
    falar('na conversa ligada depois', decisao - 10.minutes, conversa: depois)
    ligar(antes, decisao - 2.minutes)
    ligar(depois, decisao + 2.minutes)

    expect(textos(described_class.new(card: card, ate: decisao).perform)).to eq(['pela outra conversa'])
  end

  it 'com a janela da avaliação, também tira o envio que falhou' do
    falar('chegou', decisao - 3.minutes)
    falar('não chegou', decisao - 2.minutes, status: :failed)

    expect(textos(described_class.new(card: card, ate: decisao, janela: :avaliacao).perform)).to eq(['chegou'])
  end
end

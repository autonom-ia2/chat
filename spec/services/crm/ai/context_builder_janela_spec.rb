require 'rails_helper'

# #1926: a avaliação de etapa lia só as 12 últimas mensagens da conversa, e o resumo (metadata.ai.summary) só existe
# quando alguém abre o card. Numa conversa longa, o preço enviado no meio ficava de fora e a IA não o via.
RSpec.describe Crm::Ai::ContextBuilder do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline) { create_crm_pipeline(account: account, user: admin).first }
  let(:inbox) { create_crm_inbox(account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let(:card) do
    account.crm_cards.create!(pipeline: pipeline, stage: pipeline.stages.first, title: 'Lead', contact: contact,
                              primary_conversation: conversation, currency: 'BRL')
  end

  def conversar(conversa, quantas, prefixo)
    quantas.times do |indice|
      create(:message, account: account, inbox: inbox, conversation: conversa, message_type: :incoming, sender: contact,
                       content: "#{prefixo} #{indice + 1}")
    end
  end

  def textos(contexto) = contexto[:recent_messages].pluck(:content)

  context 'with a single conversation' do
    before { conversar(conversation, 45, 'msg') }

    it 'a avaliação de etapa lê até MAX_MESSAGES_CAP mensagens, as mais recentes' do
      lidas = textos(described_class.new(card: card, janela: :avaliacao).perform)

      expect(lidas.size).to eq(described_class::MAX_MESSAGES_CAP)
      expect(lidas.first).to eq('msg 6')
      expect(lidas.last).to eq('msg 45')
    end

    it 'a avaliação do card (Evaluator) usa essa janela' do
      classificador = Crm::Ai::Evaluator.new(card: card).stage_classifier(client: instance_double(Crm::Ai::ResponsesClient))

      expect(classificador.conversa[:recent_messages].size).to eq(described_class::MAX_MESSAGES_CAP)
    end

    it 'os outros leitores seguem com as MAX_RECENT_MESSAGES de sempre' do
      lidas = textos(described_class.new(card: card).perform)

      expect(lidas.size).to eq(described_class::MAX_RECENT_MESSAGES)
      expect(lidas.last).to eq('msg 45')
    end
  end

  context 'with two conversations' do
    let(:outra) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }

    before do
      Crm::CardConversation.create!(account: account, card: card, conversation: outra)
      conversar(outra, 30, 'antiga')
      conversar(conversation, 30, 'nova')
    end

    it 'divide a janela entre as conversas: a movimentada não toma a vez da outra' do
      lidas = textos(described_class.new(card: card.reload, janela: :avaliacao).perform)

      metade = described_class::MAX_MESSAGES_CAP / 2
      expect(lidas.count { |texto| texto.start_with?('antiga') }).to eq(metade)
      expect(lidas.count { |texto| texto.start_with?('nova') }).to eq(metade)
    end
  end
end

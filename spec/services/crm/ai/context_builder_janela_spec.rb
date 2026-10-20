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

    # Pega (Codex, #1926): a conjunta recortar de novo em 12 o que a avaliação do card lê do outro canal.
    it 'a conjunta leva do outro card o mesmo recorte que a avaliação dele lê de cada uma das duas conversas' do
      expect(Crm::Ai::OutrasConversas::MAX_POR_CARD).to eq(described_class::MAX_MESSAGES_CAP / 2)
    end
  end

  # Pega (revisão, #1926): com 4 conversas, o piso de 12 por conversa somava 48 e o teto cortava a mais antiga por id.
  context 'with four conversations' do
    before do
      3.times do |indice|
        outra = create_crm_conversation(account: account, inbox: inbox, contact: contact)
        Crm::CardConversation.create!(account: account, card: card, conversation: outra)
        conversar(outra, 15, "conversa #{indice}")
      end
      conversar(conversation, 15, 'principal')
    end

    it 'cada conversa fica com a sua parte e nenhuma some, sem passar do teto', :aggregate_failures do
      lidas = textos(described_class.new(card: card.reload, janela: :avaliacao).perform)
      parte = described_class::MAX_MESSAGES_CAP / 4

      expect(lidas.size).to eq(described_class::MAX_MESSAGES_CAP)
      ['conversa 0', 'conversa 1', 'conversa 2', 'principal'].each do |prefixo|
        expect(lidas.count { |texto| texto.start_with?(prefixo) }).to eq(parte)
      end
    end
  end

  # Pega (revisão, #1926): áudio ou imagem que a avaliação lê, mas fora das 12 últimas, chegar sem conteúdo.
  context 'with media outside the last 12 messages' do
    before do
      conversar(conversation, 5, 'antes')
      com_foto = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                                  sender: contact, content: 'foto da proposta')
      com_foto.attachments.create!(account: account, file_type: :image, external_url: 'https://exemplo.com/proposta.jpg')
      conversar(conversation, 20, 'depois')
    end

    it 'o MediaEnricher prepara a mídia na mesma janela que a avaliação lê' do
      pendentes = Crm::Ai::MediaEnricher.new(card: card).send(:pending_attachments)

      expect(pendentes.map { |anexo| anexo.message.content }).to eq(['foto da proposta'])
    end
  end
end

require 'rails_helper'

# IA entende a conversa F4, de ponta a ponta (sem IA de verdade): a foto, o áudio e o PDF chegam, são lidos uma vez na
# chegada, e a IA de assunto (Estado da janela), o job do assunto (leitura em linha antes da pergunta) e a IA de etapa
# (ContextBuilder) leem o mesmo texto. Sem a flag, tudo como antes: a mensagem só de mídia não existe para a IA de
# assunto e o PDF é "[documento recebido]".
RSpec.describe Crm::Ai::LeitorDeMidia do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create_crm_inbox(account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let(:legendas) { instance_double(Crm::Ai::VisionCaptioner, caption: 'foto de um produto com defeito') }
  let(:transcricoes) { instance_double(Crm::Ai::TranscriptionClient, transcribe: 'quero falar sobre o pedido') }

  def chegada(conteudo = nil, tipo: :incoming)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: tipo, content: conteudo)
  end

  def estado_do_assunto(mensagem)
    Autonomia::Decisores::Estado.new(conversation: conversation, message: mensagem, leituras: Crm::Subjects::Identifier::LEITURAS,
                                     **Crm::Subjects.janela(account))
  end

  def avisar_chegada(mensagem)
    Crm::ConversationObserverListener.instance.message_created(
      Events::Base.new('message.created', Time.zone.now, message: mensagem.reload)
    )
  end

  before do
    allow(Crm::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k', source: 'teste' }))
    allow(Crm::Ai::VisionCaptioner).to receive(:new).and_return(legendas)
    allow(Crm::Ai::TranscriptionClient).to receive(:new).and_return(transcricoes)
    account.crm_inbox_settings.find_or_initialize_by(inbox: inbox).update!(crm_enabled: true, subject_ai_mode: :auto)
    clear_enqueued_jobs
  end

  describe 'com a flag' do
    before { account.enable_features!(described_class::FLAG) }

    it 'a foto lida na chegada chega à IA de assunto, com o texto da mensagem', :aggregate_failures do
      mensagem = chegada('olha isso')
      anexar_imagem(mensagem)

      avisar_chegada(mensagem)
      perform_enqueued_jobs(only: Crm::Ai::LerMidiaJob)

      expect(estado_do_assunto(mensagem).conversa[:messages].last).to eq("Customer: olha isso\n[imagem]: foto de um produto com defeito")
    end

    it 'a mensagem só de áudio deixa de ser vazia para a IA de assunto', :aggregate_failures do
      mensagem = chegada
      anexar_audio(mensagem)

      avisar_chegada(mensagem)
      perform_enqueued_jobs(only: Crm::Ai::LerMidiaJob)
      estado = estado_do_assunto(mensagem)

      expect(estado.vazio?).to be(false)
      expect(estado.conversa[:messages].last).to eq('Customer: [áudio transcrito]: quero falar sobre o pedido')
    end

    it 'anexo ainda sem leitura não vira mensagem para a IA de assunto' do
      mensagem = chegada
      anexar_imagem(mensagem, meta: { 'crm_ai_image_done' => true })

      expect(estado_do_assunto(mensagem).vazio?).to be(true)
    end

    it 'mensagem só com anexo sem leitura não ocupa a vaga de uma mensagem com texto na janela', :aggregate_failures do
      pedido = chegada('preciso de ajuda com o meu pedido')
      ouvido = chegada
      anexar_audio(ouvido, meta: { 'transcribed_text' => 'é urgente' })
      video = chegada
      video.attachments.create!(account: account, file_type: :video, external_url: 'https://exemplo.invalid/video.mp4')
      estado = Autonomia::Decisores::Estado.new(conversation: conversation, message: video, leituras: Crm::Subjects::Identifier::LEITURAS,
                                                **Crm::Subjects.janela(account), max_mensagens: 2)

      expect(estado.conversa[:messages]).to eq(['Customer: preciso de ajuda com o meu pedido', 'Customer: [áudio transcrito]: é urgente'])
      expect(pedido).to be_persisted
    end

    it 'o job do assunto lê em linha o que a chegada ainda não leu, antes de perguntar; o marco sai', :aggregate_failures do
      mensagem = chegada
      foto = anexar_imagem(mensagem)
      lido_antes_da_pergunta = nil
      allow(Crm::Subjects::Identifier).to receive(:new) do |**|
        lido_antes_da_pergunta = foto.reload.meta['ai_caption']
        instance_double(Crm::Subjects::Identifier, perform: nil)
      end
      allow(Crm::Subjects::Marco).to receive(:gravar)

      Crm::Subjects::IdentifyJob.perform_now(conversation.id, mensagem.id)

      expect(lido_antes_da_pergunta).to eq('foto de um produto com defeito')
      expect(Crm::Subjects::Marco).to have_received(:gravar).with(conversation.id, mensagem.id)
    end

    it 'a falha da leitura em linha não impede a pergunta nem o marco', :aggregate_failures do
      mensagem = chegada
      anexar_imagem(mensagem)
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_raise(ActiveRecord::ConnectionTimeoutError)
      identifier = instance_double(Crm::Subjects::Identifier, perform: nil)
      allow(Crm::Subjects::Identifier).to receive(:new).and_return(identifier)
      allow(Crm::Subjects::Marco).to receive(:gravar)

      Crm::Subjects::IdentifyJob.perform_now(conversation.id, mensagem.id)

      expect(identifier).to have_received(:perform)
      expect(Crm::Subjects::Marco).to have_received(:gravar).with(conversation.id, mensagem.id)
    end

    it 'a IA de etapa lê o texto do PDF que a equipe mandou', :aggregate_failures do
      pipeline = create_crm_pipeline(account: account, user: admin).first
      card = account.crm_cards.create!(pipeline: pipeline, stage: pipeline.stages.first, title: 'Card', contact: contact,
                                       primary_conversation: conversation, currency: 'BRL')
      mensagem = chegada('segue a proposta', tipo: :outgoing)
      anexar_pdf(mensagem, 'Proposta com valor total de 1500', nome: 'proposta.pdf')

      avisar_chegada(mensagem)
      perform_enqueued_jobs(only: Crm::Ai::LerMidiaJob)
      conteudos = Crm::Ai::ContextBuilder.new(card: card.reload).perform[:recent_messages].pluck(:content)

      expect(conteudos.last).to include('segue a proposta', '[documento proposta.pdf]: Proposta com valor total de 1500')
    end

    # Pega (revisão adversarial F4): a avaliação de etapa (MediaEnricher) pagar mais fotos de uma mensagem do que o teto
    # por mensagem da chegada.
    it 'a avaliação de etapa respeita o teto por mensagem do leitor', :aggregate_failures do
      allow(Crm::Ai::Config).to receive(:media_enabled?).and_return(true)
      pipeline = create_crm_pipeline(account: account, user: admin).first
      card = account.crm_cards.create!(pipeline: pipeline, stage: pipeline.stages.first, title: 'Card', contact: contact,
                                       primary_conversation: conversation, currency: 'BRL')
      mensagem = chegada('fotos')
      fotos = Array.new(described_class::MAX_POR_MENSAGEM[:imagem] + 2) { anexar_imagem(mensagem) }

      Crm::Ai::MediaEnricher.new(card: card).perform

      expect(legendas).to have_received(:caption).exactly(described_class::MAX_POR_MENSAGEM[:imagem]).times
      expect(fotos.last(2).map { |foto| foto.reload.meta.to_h }).to all(satisfy { |meta| !meta.key?('crm_ai_image_done') })
    end
  end

  describe 'sem a flag' do
    it 'nada é lido na chegada e a mensagem só de mídia segue vazia para a IA de assunto', :aggregate_failures do
      mensagem = chegada
      anexar_imagem(mensagem)

      avisar_chegada(mensagem)

      expect(Crm::Ai::LerMidiaJob).not_to have_been_enqueued
      expect(estado_do_assunto(mensagem).vazio?).to be(true)
    end

    it 'o job do assunto não lê nada em linha' do
      mensagem = chegada
      anexar_imagem(mensagem)
      allow(Crm::Subjects::Identifier).to receive(:new).and_return(instance_double(Crm::Subjects::Identifier, perform: nil))
      allow(Crm::Subjects::Marco).to receive(:gravar)

      Crm::Subjects::IdentifyJob.perform_now(conversation.id, mensagem.id)

      expect(legendas).not_to have_received(:caption)
    end

    it 'a IA de etapa segue lendo o PDF como "documento recebido"' do
      pipeline = create_crm_pipeline(account: account, user: admin).first
      card = account.crm_cards.create!(pipeline: pipeline, stage: pipeline.stages.first, title: 'Card', contact: contact,
                                       primary_conversation: conversation, currency: 'BRL')
      mensagem = chegada('segue a proposta', tipo: :outgoing)
      pdf = anexar_pdf(mensagem, 'Proposta')
      pdf.update!(meta: { 'ai_text' => 'Proposta', 'crm_ai_pdf_done' => true })

      conteudos = Crm::Ai::ContextBuilder.new(card: card.reload).perform[:recent_messages].pluck(:content)

      expect(conteudos.last).to eq("segue a proposta\n[documento recebido]")
    end
  end
end

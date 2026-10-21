require 'rails_helper'

# IA entende a conversa F4: o leitor de mídia na chegada. Sem chamar IA de verdade: a visão e a transcrição são dublês;
# o PDF é lido de verdade (camada de texto, local).
RSpec.describe Crm::Ai::LeitorDeMidia do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:inbox) { create_crm_inbox(account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let(:legendas) { instance_double(Crm::Ai::VisionCaptioner, caption: 'descrição da foto') }
  let(:transcricoes) { instance_double(Crm::Ai::TranscriptionClient, transcribe: 'texto do áudio') }

  def mensagem(tipo = :incoming, conteudo = nil)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: tipo, content: conteudo)
  end

  def meta(anexo) = anexo.reload.meta.to_h

  before do
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k', source: 'teste' }))
    allow(Crm::Ai::VisionCaptioner).to receive(:new).and_return(legendas)
    allow(Crm::Ai::TranscriptionClient).to receive(:new).and_return(transcricoes)
  end

  describe 'sem a flag' do
    it 'não lê nada e não paga nada', :aggregate_failures do
      foto = anexar_imagem(mensagem)

      expect(described_class.new(foto.message).perform).to eq(0)
      expect(meta(foto)).not_to have_key('ai_caption')
      expect(legendas).not_to have_received(:caption)
    end
  end

  describe 'com a flag' do
    before { account.enable_features!(described_class::FLAG) }

    it 'descreve a foto e não paga de novo na segunda leitura', :aggregate_failures do
      foto = anexar_imagem(mensagem)

      expect(described_class.new(foto.message).perform).to eq(1)
      expect(described_class.new(foto.message.reload).perform).to eq(0)
      expect(meta(foto)).to include('ai_caption' => 'descrição da foto', 'crm_ai_image_done' => true)
      expect(legendas).to have_received(:caption).once
    end

    it 'transcreve o áudio; o já transcrito (EE ou Agentes IA) não paga', :aggregate_failures do
      novo = anexar_audio(mensagem)
      transcrito = anexar_audio(mensagem, meta: { 'transcribed_text' => 'já transcrito' })

      described_class.new(novo.message).perform
      described_class.new(transcrito.message).perform

      expect(meta(novo)).to include('transcribed_text' => 'texto do áudio', 'crm_ai_audio_done' => true)
      expect(meta(transcrito)['transcribed_text']).to eq('já transcrito')
      expect(transcricoes).to have_received(:transcribe).once
    end

    it 'lê a camada de texto do PDF, em NFC, sem chamar IA', :aggregate_failures do
      pdf = anexar_pdf(mensagem, 'Pedido de orçamento número 42')

      described_class.new(pdf.message).perform

      expect(meta(pdf)['ai_text']).to include('Pedido de orçamento número 42')
      expect(meta(pdf)['ai_text']).to eq(meta(pdf)['ai_text'].unicode_normalize(:nfc))
      expect(meta(pdf)['crm_ai_pdf_done']).to be(true)
      expect(Crm::Ai::VisionCaptioner).not_to have_received(:new)
    end

    it 'PDF sem camada de texto fica marcado e sem texto (sem OCR)', :aggregate_failures do
      pdf = anexar_pdf(mensagem, nil)

      described_class.new(pdf.message).perform

      expect(meta(pdf)['crm_ai_pdf_done']).to be(true)
      expect(meta(pdf)).not_to have_key('ai_text')
    end

    it 'arquivo que não é PDF não é lido' do
      outro = mensagem.attachments.create!(account: account, file_type: :file,
                                           file: Rack::Test::UploadedFile.new(StringIO.new('a;b'), 'text/csv', original_filename: 'x.csv'))

      expect(described_class.new(outro.message).perform).to eq(0)
    end

    it 'corta o texto do PDF no teto' do
      stub_const("#{described_class}::MAX_CARACTERES_DO_PDF", 10)
      pdf = anexar_pdf(mensagem, 'Um texto bem mais longo do que dez letras')

      described_class.new(pdf.message).perform

      expect(meta(pdf)['ai_text'].length).to eq(10)
    end

    it 'respeita o teto por mensagem (4 fotos)', :aggregate_failures do
      chegada = mensagem
      fotos = Array.new(5) { anexar_imagem(chegada) }

      expect(described_class.new(chegada).perform).to eq(4)
      expect(meta(fotos.last)).not_to have_key('crm_ai_image_done')
    end

    it 'passou do teto do dia da conta: não lê nem marca', :aggregate_failures do
      stub_const("#{described_class}::MAX_LEITURAS_POR_DIA", 1)
      primeira = anexar_imagem(mensagem)
      segunda = anexar_imagem(mensagem)

      described_class.new(primeira.message).perform
      described_class.new(segunda.message).perform

      expect(meta(primeira)['crm_ai_image_done']).to be(true)
      expect(meta(segunda)).not_to have_key('crm_ai_image_done')
      expect(legendas).to have_received(:caption).once
    end

    it 'a falha também marca o anexo, para não tentar para sempre', :aggregate_failures do
      allow(legendas).to receive(:caption).and_raise(StandardError, 'falhou')
      foto = anexar_imagem(mensagem)

      described_class.new(foto.message).perform

      expect(meta(foto)['crm_ai_image_done']).to be(true)
      expect(meta(foto)).not_to have_key('ai_caption')
    end

    it 'sem credencial da conta: não lê foto nem áudio, e o PDF segue', :aggregate_failures do
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: nil))
      chegada = mensagem
      foto = anexar_imagem(chegada)
      pdf = anexar_pdf(chegada, 'Texto do documento')

      described_class.new(chegada).perform

      expect(meta(foto)).not_to have_key('crm_ai_image_done')
      expect(meta(pdf)['ai_text']).to include('Texto do documento')
    end

    it 'trava por anexo: quem chega depois encontra lido e não paga de novo', :aggregate_failures do
      foto = anexar_imagem(mensagem)
      antiga = Attachment.find(foto.id)
      described_class.new(foto.message).perform

      expect(described_class.new(foto.message).ler(antiga)).to be(false)
      expect(legendas).to have_received(:caption).once
    end

    it 'com a mídia desligada na instalação, não está ligada' do
      allow(Crm::Ai::Config).to receive(:media_enabled?).and_return(false)

      expect(described_class.ligada?(account)).to be(false)
    end
  end

  describe '.ler_depois' do
    def ligar_crm = account.crm_inbox_settings.find_or_initialize_by(inbox: inbox).update!(crm_enabled: true)

    before { clear_enqueued_jobs }

    it 'com a flag, anexo e CRM na caixa, enfileira a leitura na fila high', :aggregate_failures do
      account.enable_features!(described_class::FLAG)
      ligar_crm
      foto = anexar_imagem(mensagem(:outgoing))

      described_class.ler_depois(foto.message)

      expect(Crm::Ai::LerMidiaJob).to have_been_enqueued.with(foto.message_id).on_queue('high')
    end

    it 'sem a flag, sem anexo ou sem CRM na caixa, não enfileira', :aggregate_failures do
      foto = anexar_imagem(mensagem)
      described_class.ler_depois(foto.message)
      account.enable_features!(described_class::FLAG)
      described_class.ler_depois(foto.message)
      ligar_crm
      described_class.ler_depois(mensagem(:incoming, 'só texto'))

      expect(Crm::Ai::LerMidiaJob).not_to have_been_enqueued
    end

    it 'nota privada com anexo não enfileira' do
      account.enable_features!(described_class::FLAG)
      ligar_crm
      nota = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, private: true)
      anexar_imagem(nota)

      described_class.ler_depois(nota)

      expect(Crm::Ai::LerMidiaJob).not_to have_been_enqueued
    end
  end

  describe '.ler_a_rajada' do
    before { account.enable_features!(described_class::FLAG) }

    it 'lê os anexos do cliente até a mensagem perguntada; a fala da equipe fica para o job da chegada', :aggregate_failures do
      do_cliente = anexar_imagem(mensagem)
      da_equipe = anexar_imagem(mensagem(:outgoing))
      perguntada = mensagem(:incoming, 'segue a foto')
      depois = anexar_imagem(mensagem)

      described_class.ler_a_rajada(conversation, perguntada)

      expect(meta(do_cliente)['crm_ai_image_done']).to be(true)
      expect(meta(da_equipe)).not_to have_key('crm_ai_image_done')
      expect(meta(depois)).not_to have_key('crm_ai_image_done')
    end

    it 'uma falha não sobe: a pergunta do assunto segue' do
      foto = anexar_imagem(mensagem)
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_raise(ActiveRecord::ConnectionTimeoutError)

      expect { described_class.ler_a_rajada(conversation, foto.message) }.not_to raise_error
    end
  end

  describe 'MediaEnricher da avaliação' do
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:pipeline) { create_crm_pipeline(account: account, user: admin).first }
    let(:card) do
      account.crm_cards.create!(pipeline: pipeline, stage: pipeline.stages.first, title: 'Card', contact: contact,
                                primary_conversation: conversation, currency: 'BRL')
    end

    it 'com a flag, lê também o PDF da janela pelo mesmo leitor', :aggregate_failures do
      account.enable_features!(described_class::FLAG)
      pdf = anexar_pdf(mensagem, 'Conteúdo do documento')

      Crm::Ai::MediaEnricher.new(card: card).perform

      expect(meta(pdf)['ai_text']).to include('Conteúdo do documento')
    end

    it 'sem a flag, o PDF segue sem leitura (como antes)' do
      pdf = anexar_pdf(mensagem, 'Conteúdo do documento')

      Crm::Ai::MediaEnricher.new(card: card).perform

      expect(meta(pdf)).not_to have_key('crm_ai_pdf_done')
    end
  end
end

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

  def mensagem(tipo = :incoming, conteudo = nil, criada_em: Time.current)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: tipo, content: conteudo,
                     created_at: criada_em)
  end

  def meta(anexo) = anexo.reload.meta.to_h

  before do
    limpar_redis_do_leitor
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

    describe 'falha da leitura (#2109)' do
      def passou_a_espera(anexo) = anexo.update!(meta: anexo.reload.meta.merge(Crm::Ai::FalhaDaMidia::PROXIMA => 1.second.ago.iso8601))

      it 'falha permanente (a API recusou o pedido) marca o anexo na hora, com o motivo', :aggregate_failures do
        allow(legendas).to receive(:caption).and_raise(Crm::Ai::ResponsesClient::Error.new('rejected', status: 400))
        foto = anexar_imagem(mensagem)

        expect(described_class.new(foto.message).perform).to eq(1)
        expect(meta(foto)).to include('crm_ai_image_done' => true, 'crm_ai_midia_falha' => 'permanente',
                                      'crm_ai_midia_erro' => 'Crm::Ai::ResponsesClient::Error')
        expect(meta(foto)).not_to have_key('ai_caption')
      end

      it 'arquivo que a API não aceita (400 na transcrição) também é permanente' do
        allow(transcricoes).to receive(:transcribe).and_raise(Faraday::BadRequestError, 'formato')
        audio = anexar_audio(mensagem)

        described_class.new(audio.message).perform

        expect(meta(audio)).to include('crm_ai_audio_done' => true, 'crm_ai_midia_falha' => 'permanente')
      end

      it 'leitura sem texto (sem fala, arquivo grande) marca sem_texto, que é definitiva' do
        allow(transcricoes).to receive(:transcribe).and_return(nil)
        audio = anexar_audio(mensagem)

        described_class.new(audio.message).perform

        expect(meta(audio)).to include('crm_ai_audio_done' => true, 'crm_ai_midia_falha' => 'sem_texto')
      end

      [Faraday::ConnectionFailed, Faraday::TimeoutError, Faraday::TooManyRequestsError, Faraday::ServerError,
       Faraday::UnauthorizedError, Faraday::SSLError, Net::ReadTimeout, Errno::EHOSTUNREACH].each do |erro|
        it "falha passageira (#{erro}) não marca, agenda a próxima tentativa e sobe para o job", :aggregate_failures do
          allow(transcricoes).to receive(:transcribe).and_raise(erro)
          audio = anexar_audio(mensagem)

          expect { described_class.new(audio.message).perform }.to raise_error(described_class::FalhaPassageira)
          expect(meta(audio)).not_to have_key('crm_ai_audio_done')
          expect(meta(audio)).to include('crm_ai_midia_tentativas' => 1, 'crm_ai_midia_erro' => erro.name)
          expect(Time.zone.parse(meta(audio)['crm_ai_midia_proxima_em'])).to be_within(5.seconds).of(1.minute.from_now)
        end
      end

      it 'a chave recusada (403) é permanente' do
        allow(legendas).to receive(:caption).and_raise(Crm::Ai::ResponsesClient::Error.new('x', status: 403))
        foto = anexar_imagem(mensagem)

        described_class.new(foto.message).perform

        expect(meta(foto)['crm_ai_midia_falha']).to eq('permanente')
      end

      it 'a API da foto ocupada (429) ou recusando a chave (401) é passageira', :aggregate_failures do
        [429, 401].each do |status|
          allow(legendas).to receive(:caption).and_raise(Crm::Ai::ResponsesClient::Error.new('x', status: status))
          foto = anexar_imagem(mensagem)

          expect { described_class.new(foto.message).perform }.to raise_error(described_class::FalhaPassageira)
          expect(meta(foto)).not_to have_key('crm_ai_image_done')
        end
      end

      it 'enquanto a próxima tentativa não vence, ninguém lê nem gasta tentativa', :aggregate_failures do
        allow(transcricoes).to receive(:transcribe).and_raise(Faraday::TimeoutError)
        audio = anexar_audio(mensagem)
        expect { described_class.new(audio.message).perform }.to raise_error(described_class::FalhaPassageira)

        expect(described_class.new(audio.message.reload, releitura: :mensagem_nova).perform).to eq(0)
        expect { described_class.ler_a_rajada(conversation, audio.message) }.not_to raise_error
        expect(transcricoes).to have_received(:transcribe).once
        expect(meta(audio)['crm_ai_midia_tentativas']).to eq(1)
      end

      it 'a próxima tentativa nunca fica para depois do fim da janela da mensagem' do
        allow(transcricoes).to receive(:transcribe).and_raise(Faraday::TimeoutError)
        audio = anexar_audio(mensagem(criada_em: 47.hours.ago), meta: { 'crm_ai_midia_tentativas' => 9 })

        expect { described_class.new(audio.message.reload).perform }.to raise_error(described_class::FalhaPassageira)

        expect(Time.zone.parse(meta(audio)['crm_ai_midia_proxima_em']))
          .to be_within(5.seconds).of(audio.message.created_at + Crm::Ai::FalhaDaMidia::JANELA_DE_RELEITURA)
      end

      it 'mensagem fora da janela de 48 h com falha passageira: marca expirado', :aggregate_failures do
        allow(transcricoes).to receive(:transcribe).and_raise(Faraday::TooManyRequestsError)
        audio = anexar_audio(mensagem(criada_em: (Crm::Ai::FalhaDaMidia::JANELA_DE_RELEITURA + 1.minute).ago))

        expect(described_class.new(audio.message.reload).perform).to eq(1)
        expect(meta(audio)).to include('crm_ai_audio_done' => true, 'crm_ai_midia_falha' => 'expirado',
                                       'crm_ai_midia_erro' => 'Faraday::TooManyRequestsError')
      end

      it 'a tentativa seguinte que dá certo lê e tira o motivo e a espera', :aggregate_failures do
        tentativas = 0
        allow(transcricoes).to receive(:transcribe) do
          tentativas += 1
          raise Faraday::TimeoutError if tentativas == 1

          'texto do áudio'
        end
        audio = anexar_audio(mensagem)

        expect { described_class.new(audio.message).perform }.to raise_error(described_class::FalhaPassageira)
        passou_a_espera(audio)
        expect(described_class.new(audio.message.reload).perform).to eq(1)
        expect(meta(audio)).to include('transcribed_text' => 'texto do áudio', 'crm_ai_audio_done' => true)
        expect(meta(audio)).not_to have_key('crm_ai_midia_proxima_em')
      end

      it 'os outros anexos da mensagem seguem; a falha passageira sobe só no fim', :aggregate_failures do
        chegada = mensagem
        audio = anexar_audio(chegada)
        foto = anexar_imagem(chegada)
        allow(transcricoes).to receive(:transcribe).and_raise(Faraday::ConnectionFailed)

        expect { described_class.new(chegada).perform }.to raise_error(described_class::FalhaPassageira)
        expect(meta(foto)['ai_caption']).to eq('descrição da foto')
        expect(meta(audio)).not_to have_key('crm_ai_audio_done')
      end

      it 'a tentativa com falha passageira conta no teto do dia (em dia de API lenta, o gasto tem limite)', :aggregate_failures do
        stub_const("#{described_class}::MAX_LEITURAS_POR_DIA", 1)
        allow(transcricoes).to receive(:transcribe).and_raise(Faraday::TimeoutError)
        audio = anexar_audio(mensagem)
        expect { described_class.new(audio.message).perform }.to raise_error(described_class::FalhaPassageira)

        foto = anexar_imagem(mensagem)

        expect(described_class.new(foto.message).perform).to eq(0)
        expect(Crm::Ai::TetoDaMidia.new(account).usado).to eq(2)
      end

      it 'anexo em leitura por outro processo (marca vigente) não é lido de novo; marca vencida é', :aggregate_failures do
        foto = anexar_imagem(mensagem, meta: { Crm::Ai::ReservaDaMidia::LENDO => 5.minutes.from_now.iso8601 })
        expect(described_class.new(foto.message).perform).to eq(0)

        foto.update!(meta: { Crm::Ai::ReservaDaMidia::LENDO => 1.second.ago.iso8601 })
        expect(described_class.new(foto.message.reload).perform).to eq(1)
        expect(meta(foto)).not_to have_key(Crm::Ai::ReservaDaMidia::LENDO)
      end

      it 'na leitura em linha, a falha passageira não sobe e o anexo fica pendente', :aggregate_failures do
        allow(transcricoes).to receive(:transcribe).and_raise(Faraday::TimeoutError)
        audio = anexar_audio(mensagem)

        expect { described_class.ler_a_rajada(conversation, audio.message) }.not_to raise_error
        expect(described_class.pendente?(audio.reload)).to be(true)
      end
    end

    # Regra do Rodrigo (23/10/2026): chegou mensagem nova, o leitor relê a mídia antiga sem texto das últimas mensagens,
    # de qualquer idade, salvo falha definitiva.
    describe 'mensagem nova relê a mídia antiga sem texto (#2109)' do
      def antiga(meta) = anexar_audio(mensagem(criada_em: 30.days.ago), meta: meta)

      it 'relê o áudio antigo marcado sem texto (antes do #2109, ou expirado) entre as últimas', :aggregate_failures do
        sem_motivo = antiga('crm_ai_audio_done' => true)
        expirado = antiga('crm_ai_audio_done' => true, 'crm_ai_midia_falha' => 'expirado')
        nova = mensagem(:incoming, 'e aí?')

        perform_enqueued_jobs { described_class.ler_a_rajada(conversation, nova) }

        expect(meta(sem_motivo)).to include('transcribed_text' => 'texto do áudio')
        expect(meta(expirado)).to include('transcribed_text' => 'texto do áudio')
        expect(meta(expirado)).not_to have_key('crm_ai_midia_falha')
      end

      it 'não relê o de falha definitiva nem o que já tem texto', :aggregate_failures do
        Crm::Ai::FalhaDaMidia::FALHAS_DEFINITIVAS.each { |falha| antiga('crm_ai_audio_done' => true, 'crm_ai_midia_falha' => falha) }
        antiga('transcribed_text' => 'já lido', 'crm_ai_audio_done' => true)

        perform_enqueued_jobs { described_class.ler_a_rajada(conversation, mensagem(:incoming, 'e aí?')) }

        expect(transcricoes).not_to have_received(:transcribe)
      end

      it 'a leitura em linha não espera a releitura: enfileira o job da chegada', :aggregate_failures do
        clear_enqueued_jobs
        antiga('crm_ai_audio_done' => true)

        described_class.ler_a_rajada(conversation, mensagem(:incoming, 'e aí?'))

        expect(transcricoes).not_to have_received(:transcribe)
        expect(Crm::Ai::LerMidiaJob).to have_been_enqueued.with(anything, 'mensagem_nova').on_queue('low').once
      end

      it 'o expirado que falha de novo só volta a ser relido depois de ESPERA_DO_EXPIRADO', :aggregate_failures do
        allow(transcricoes).to receive(:transcribe).and_raise(Faraday::TimeoutError)
        anexo = antiga('crm_ai_audio_done' => true, 'crm_ai_midia_falha' => 'expirado')

        described_class.new(Message.find(anexo.message_id), releitura: :mensagem_nova).perform
        expect(described_class.new(Message.find(anexo.message_id), releitura: :mensagem_nova).escolhidos).to be_empty
        travel(Crm::Ai::FalhaDaMidia::ESPERA_DO_EXPIRADO + 1.minute) do
          expect(described_class.new(Message.find(anexo.message_id), releitura: :mensagem_nova).escolhidos).to eq([anexo])
        end
        expect(transcricoes).to have_received(:transcribe).once
      end

      # Pega: o expirado (ex.: chave recusada, 401) ser relido uma vez por hora sem fim enquanto a conversa tem mensagem.
      it 'o expirado para de vez depois de MAX_RELEITURAS_DO_EXPIRADO falhas, com aviso', :aggregate_failures do
        allow(transcricoes).to receive(:transcribe).and_raise(Faraday::UnauthorizedError)
        allow(Rails.logger).to receive(:warn)
        anexo = antiga('crm_ai_audio_done' => true, 'crm_ai_midia_falha' => 'expirado')
        maximo = Crm::Ai::FalhaDaMidia::MAX_RELEITURAS_DO_EXPIRADO

        maximo.times do |vez|
          travel((vez + 1) * (Crm::Ai::FalhaDaMidia::ESPERA_DO_EXPIRADO + 1.minute)) do
            described_class.new(Message.find(anexo.message_id), releitura: :mensagem_nova).perform
          end
        end

        expect(meta(anexo)).to include('crm_ai_midia_falha' => 'expirado_esgotado', 'crm_ai_midia_releituras_do_expirado' => maximo)
        expect(Rails.logger).to have_received(:warn).with(a_string_including('esgotou=true'))
        travel(1.day) do
          expect(described_class.new(Message.find(anexo.message_id), releitura: :mensagem_nova).escolhidos).to be_empty
        end
        expect(transcricoes).to have_received(:transcribe).exactly(maximo).times
      end

      it 'a avaliação do card (sem mensagem nova) não relê o marcado sem texto' do
        anexo = antiga('crm_ai_audio_done' => true)

        expect(described_class.new(anexo.message).escolhidos).to be_empty
      end
    end

    # Pega (revisão adversarial F4): um erro nosso ser engolido e o anexo marcado como lido, sem nunca ser lido.
    it 'erro interno propaga e não marca o anexo', :aggregate_failures do
      allow(legendas).to receive(:caption).and_raise(NoMethodError, 'bug')
      foto = anexar_imagem(mensagem)

      expect { described_class.new(foto.message).perform }.to raise_error(NoMethodError)
      expect(meta(foto)).not_to have_key('crm_ai_image_done')
      expect(meta(foto)).not_to have_key(Crm::Ai::ReservaDaMidia::LENDO)
    end

    describe 'arquivo que ainda não chegou ao storage (corrida com o upload)' do
      before { allow(legendas).to receive(:caption).and_raise(ActiveStorage::FileNotFoundError) }

      it 'não marca o anexo e sobe, para o job tentar de novo', :aggregate_failures do
        foto = anexar_imagem(mensagem)

        expect { described_class.new(foto.message).perform }.to raise_error(ActiveStorage::FileNotFoundError)
        expect(meta(foto)).not_to have_key('crm_ai_image_done')
        expect(described_class.pendente?(foto.reload)).to be(true)
      end

      it 'a tentativa que falhou não conta no teto do dia', :aggregate_failures do
        stub_const("#{described_class}::MAX_LEITURAS_POR_DIA", 1)
        ausente = anexar_imagem(mensagem)
        expect { described_class.new(ausente.message).perform }.to raise_error(ActiveStorage::FileNotFoundError)

        allow(legendas).to receive(:caption).and_return('descrição da foto')
        chegou = anexar_imagem(mensagem)

        expect(chegou.message_id).not_to eq(ausente.message_id)
        expect(described_class.new(chegou.message).perform).to eq(1)
        expect(meta(chegou)['ai_caption']).to eq('descrição da foto')
      end

      it 'na última tentativa, marca o anexo sem texto', :aggregate_failures do
        foto = anexar_imagem(mensagem)

        expect(described_class.new(foto.message, ultima_tentativa: true).perform).to eq(1)
        expect(meta(foto)['crm_ai_image_done']).to be(true)
        expect(meta(foto)).not_to have_key('ai_caption')
      end

      it 'na leitura em linha, não marca, não sobe e as outras mensagens da rajada seguem', :aggregate_failures do
        antiga = anexar_imagem(mensagem)
        nova = anexar_imagem(mensagem)
        allow(legendas).to receive(:caption) do |anexo|
          raise ActiveStorage::FileNotFoundError if anexo.id == nova.id

          'descrição da foto'
        end

        expect { described_class.ler_a_rajada(conversation, nova.message) }.not_to raise_error
        expect(legendas).to have_received(:caption).twice
        expect(meta(nova)).not_to have_key('crm_ai_image_done')
        expect(meta(antiga)['ai_caption']).to eq('descrição da foto')
      end
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

    it 'com a flag, o arquivo que ainda não chegou fica pendente e a avaliação segue', :aggregate_failures do
      account.enable_features!(described_class::FLAG)
      allow(legendas).to receive(:caption).and_raise(ActiveStorage::FileNotFoundError)
      foto = anexar_imagem(mensagem)

      expect(described_class.ligada?(account)).to be(true)
      expect { Crm::Ai::MediaEnricher.new(card: card).perform }.not_to raise_error
      expect(legendas).to have_received(:caption)
      expect(meta(foto)).not_to have_key('crm_ai_image_done')
    end

    it 'com a flag, a falha passageira fica pendente e a avaliação segue', :aggregate_failures do
      account.enable_features!(described_class::FLAG)
      allow(legendas).to receive(:caption).and_raise(Faraday::TooManyRequestsError)
      foto = anexar_imagem(mensagem)

      expect { Crm::Ai::MediaEnricher.new(card: card).perform }.not_to raise_error
      expect(meta(foto)).not_to have_key('crm_ai_image_done')
      expect(meta(foto)['crm_ai_midia_tentativas']).to eq(1)
    end

    it 'sem a flag, o PDF segue sem leitura (como antes)' do
      pdf = anexar_pdf(mensagem, 'Conteúdo do documento')

      Crm::Ai::MediaEnricher.new(card: card).perform

      expect(meta(pdf)).not_to have_key('crm_ai_pdf_done')
    end
  end
end

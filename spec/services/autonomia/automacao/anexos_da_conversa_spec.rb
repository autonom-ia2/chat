require 'rails_helper'

# G20 (#2669): os anexos que o passo de IA lê com `le: anexos`. Só os da conversa da execução; foto e PDF vão como estão,
# áudio pela transcrição guardada; o que passa do limite técnico do provedor vira motivo, antes de pagar a IA.
RSpec.describe Autonomia::Automacao::AnexosDaConversa do
  let(:account) { create(:account) }
  let(:conversa) { create(:conversation, account: account) }
  let(:modelo) { Crm::Ai::Config::VISION_MODEL }

  def mensagem(alvo = conversa, tipo: :incoming, privada: false)
    create(:message, conversation: alvo, account: account, message_type: tipo, private: privada, content: nil)
  end

  def anexar(para, arquivo, tipo, content_type, meta: {})
    anexo = para.attachments.new(account_id: account.id, file_type: tipo, meta: meta)
    anexo.file.attach(io: Rails.root.join("spec/assets/#{arquivo}").open, filename: arquivo, content_type: content_type)
    anexo.save!
    anexo
  end

  def anexos(alvo = conversa) = described_class.new(alvo)

  it 'foto e PDF vão como estão, na ordem das mensagens; áudio vai pela transcrição', :aggregate_failures do
    anexar(mensagem, 'sample.pdf', :file, 'application/pdf')
    anexar(mensagem, 'avatar.png', :image, 'image/png')
    anexar(mensagem, 'sample.mp3', :audio, 'audio/mpeg', meta: { 'transcribed_text' => 'Tenho cinco anos de experiência.' })

    partes = anexos.partes(modelo: modelo)

    expect(partes.pluck(:type)).to eq(%w[input_file input_image input_text])
    expect(partes[0]).to include(filename: 'sample.pdf')
    expect(partes[0][:file_data]).to start_with('data:application/pdf;base64,')
    expect(partes[1][:image_url]).to start_with('data:image/png;base64,')
    expect(partes[2][:text]).to include('Tenho cinco anos de experiência.')
  end

  it 'só da conversa da execução, das mensagens do cliente que não são privadas', :aggregate_failures do
    outra = create(:conversation, account: account, contact: conversa.contact)
    anexar(mensagem(outra), 'sample.pdf', :file, 'application/pdf')
    anexar(mensagem(tipo: :outgoing), 'sample.pdf', :file, 'application/pdf')
    anexar(mensagem(privada: true), 'sample.pdf', :file, 'application/pdf')

    expect([anexos.quantos, anexos.algum?]).to eq([0, false])
    expect(anexos(outra).quantos).to eq(1)
  end

  it 'lê as últimas mensagens com anexo, a mesma janela do Estado' do
    (described_class::MAX_MENSAGENS + 1).times { anexar(mensagem, 'avatar.png', :image, 'image/png') }

    expect(anexos.quantos).to eq(described_class::MAX_MENSAGENS)
  end

  it 'vídeo não é documento e fica de fora' do
    anexar(mensagem, 'sample.mp4', :video, 'video/mp4')

    expect(anexos.algum?).to be(false)
  end

  describe 'o que faz o passo pular' do
    it 'arquivo que não é PDF: anexo_fora_do_formato' do
      anexar(mensagem, 'contacts.csv', :file, 'text/csv')

      expect(anexos.motivo(modelo: modelo)).to eq('anexo_fora_do_formato')
    end

    it 'imagem num formato que o provedor não lê: anexo_fora_do_formato' do
      # O ActiveStorage confere o tipo pelos bytes: um arquivo que não é PNG, JPEG, WebP nem GIF.
      anexar(mensagem, 'sample.mov', :image, 'video/quicktime')

      expect(anexos.motivo(modelo: modelo)).to eq('anexo_fora_do_formato')
    end

    it 'imagem acima do limite: anexo_grande_demais' do
      stub_const("#{described_class}::LIMITE_DA_IMAGEM", 10)
      anexar(mensagem, 'avatar.png', :image, 'image/png')

      expect(anexos.motivo(modelo: modelo)).to eq('anexo_grande_demais')
    end

    it 'PDFs que somados passam do limite do provedor: anexo_grande_demais' do
      stub_const("#{described_class}::LIMITE_DOS_ARQUIVOS", 4_000)
      2.times { anexar(mensagem, 'sample.pdf', :file, 'application/pdf') }

      expect(anexos.motivo(modelo: modelo)).to eq('anexo_grande_demais')
    end

    it 'áudio sem transcrição: anexo_sem_leitura' do
      anexar(mensagem, 'sample.mp3', :audio, 'audio/mpeg')

      expect(anexos.motivo(modelo: modelo)).to eq('anexo_sem_leitura')
    end

    it 'modelo sem visão com foto ou PDF: modelo_sem_imagem; só áudio transcrito passa', :aggregate_failures do
      audio = mensagem
      anexar(audio, 'sample.mp3', :audio, 'audio/mpeg', meta: { 'transcribed_text' => 'oi' })
      expect(anexos.motivo(modelo: 'modelo-so-texto')).to be_nil

      anexar(mensagem, 'avatar.png', :image, 'image/png')
      expect(anexos.motivo(modelo: 'modelo-so-texto')).to eq('modelo_sem_imagem')
      expect { anexos.partes(modelo: 'modelo-so-texto') }.to raise_error(described_class::Recusa, 'modelo_sem_imagem')
    end

    it 'arquivo que sumiu do storage na hora de ler: anexo_sem_leitura' do
      anexar(mensagem, 'sample.pdf', :file, 'application/pdf')
      allow_any_instance_of(ActiveStorage::Blob).to receive(:open).and_raise(ActiveStorage::FileNotFoundError) # rubocop:disable RSpec/AnyInstance

      expect { anexos.partes(modelo: modelo) }.to raise_error(described_class::Recusa, 'anexo_sem_leitura')
    end
  end

  describe '.leitura' do
    let(:vazio) { instance_double(Autonomia::Decisores::Estado, vazio?: true) }

    it 'sem texto, mas com o anexo pedido, a leitura não é vazia; sem pedir anexos, continua vazia', :aggregate_failures do
      anexar(mensagem, 'sample.pdf', :file, 'application/pdf')

      expect(described_class.leitura(vazio, { 'le' => %w[anexos] }, conversa).vazio?).to be(false)
      expect(described_class.leitura(vazio, { 'le' => %w[mensagens_recentes] }, conversa).vazio?).to be(true)
    end
  end
end

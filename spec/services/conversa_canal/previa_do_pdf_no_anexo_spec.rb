require 'rails_helper'

# #1702: o cartão do documento mostra a 1ª página do PDF, como no app. A miniatura (`thumb_url`) do PDF vira a prévia
# gerada pelo Active Storage (Poppler, que a imagem de produção tem); sem a pele, o PDF segue sem miniatura.
describe ConversaCanal::PreviaDoPdfNoAnexo do
  let(:message) { create(:message) }

  before do
    message.account.enable_features!('conversa_cara_do_canal')
    allow(ActiveStorage::Previewer::PopplerPDFPreviewer).to receive(:pdftoppm_exists?).and_return(true)
  end

  # O Active Storage confere o tipo pelo conteúdo: o texto precisa ser texto de verdade.
  def anexo(content_type: 'application/pdf', filename: 'boleto.pdf', conteudo: '%PDF-1.4 fake')
    message.attachments.create!(account_id: message.account_id, file_type: :file,
                                file: { io: StringIO.new(conteudo), filename: filename, content_type: content_type })
  end

  it 'only the PDF previewer of the skin is enabled (video stays without preview)' do
    expect(ActiveStorage.previewers).to eq([ConversaCanal::PreviaDoPdfDaPele])
  end

  it 'the public preview route does not draw a PDF from an account without the skin' do
    blob = anexo.file.blob
    expect(ConversaCanal::PreviaDoPdfDaPele.accept?(blob)).to be(true)

    message.account.disable_features!('conversa_cara_do_canal')
    expect(ConversaCanal::PreviaDoPdfDaPele.accept?(blob.reload)).to be(false)
    expect(blob.previewable?).to be(false)
  end

  it 'gives the PDF a thumbnail that is the preview of the first page' do
    thumb = anexo.thumb_url

    expect(thumb).to include('/rails/active_storage/representations/')
    expect(anexo.push_event_data[:thumb_url]).to include('/rails/active_storage/representations/')
  end

  it 'with the skin off, the PDF goes out without thumbnail, as on main' do
    message.account.disable_features!('conversa_cara_do_canal')

    expect(anexo.thumb_url).to eq('')
  end

  it 'leaves other documents without thumbnail' do
    expect(anexo(content_type: 'text/plain', filename: 'nota.txt', conteudo: 'só texto').thumb_url).to eq('')
  end

  it 'without pdftoppm on the machine, the PDF goes out without thumbnail' do
    allow(ActiveStorage::Previewer::PopplerPDFPreviewer).to receive(:pdftoppm_exists?).and_return(false)

    expect(anexo.thumb_url).to eq('')
  end

  it 'a PDF that cannot be previewed falls back to no thumbnail' do
    documento = anexo
    allow(documento.file).to receive(:preview).and_raise(ActiveStorage::UnpreviewableError.new('sem prévia'))

    expect(Rails.logger).to receive(:warn).with(/Unpreviewable PDF attachment: #{documento.id}/)
    expect(documento.thumb_url).to eq('')
  end

  describe 'PDF the Poppler cannot draw (password, broken)' do
    # O pdftoppm sai com erro: é o que o Active Storage levanta no PDF com senha.
    def poppler_falha
      falho = instance_double(ActiveStorage::Previewer::PopplerPDFPreviewer)
      allow(falho).to receive(:preview).and_raise(ActiveStorage::PreviewError, 'pdftoppm failed (status 1): Incorrect password')
      allow(ConversaCanal::PreviaDoPdfDaPele).to receive(:new).and_return(falho)
      falho
    end

    it 'marks the blob when the preview fails and stops offering it' do
      documento = anexo
      falho = poppler_falha

      expect { documento.file.preview(resize_to_limit: described_class::TAMANHO_DA_PREVIA).processed }
        .to raise_error(ActiveStorage::PreviewError)
      expect(documento.file.blob.reload.metadata).to include('previa_falhou' => true)

      recarregado = Attachment.find(documento.id)
      expect(recarregado.thumb_url).to eq('')
      expect(recarregado.push_event_data[:thumb_url]).to eq('')
      expect(falho).to have_received(:preview).once
    end

    it 'the request for the preview image marks the blob (where the error happens)', type: :request do
      documento = anexo
      poppler_falha

      get documento.thumb_url

      expect(response).to have_http_status(:internal_server_error)
      expect(documento.file.blob.reload.metadata['previa_falhou']).to be(true)
      expect(Attachment.find(documento.id).thumb_url).to eq('')
    end

    it 'does not mark a storage error (it may work next time)' do
      documento = anexo
      falho = instance_double(ActiveStorage::Previewer::PopplerPDFPreviewer)
      allow(falho).to receive(:preview).and_raise(ActiveStorage::FileNotFoundError)
      allow(ConversaCanal::PreviaDoPdfDaPele).to receive(:new).and_return(falho)

      expect { documento.file.preview(resize_to_limit: described_class::TAMANHO_DA_PREVIA).processed }
        .to raise_error(ActiveStorage::FileNotFoundError)
      expect(documento.file.blob.reload.metadata).not_to have_key('previa_falhou')
      expect(Attachment.find(documento.id).thumb_url).to include('/rails/active_storage/representations/')
    end
  end

  it 'keeps the image thumbnail as it was' do
    foto = message.attachments.create!(account_id: message.account_id, file_type: :image,
                                       file: fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png'))

    expect(foto.thumb_url).to include('/rails/active_storage/representations/')
  end
end

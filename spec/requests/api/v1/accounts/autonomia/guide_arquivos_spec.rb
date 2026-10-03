require 'rails_helper'

# #857 — arquivo anexado na conversa com o Guia, pela API que a tela usa.
RSpec.describe 'Guia da Plataforma — arquivos da conversa', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/autonomia/guide" }

  before { allow(Autonomia::Guide::Seed).to receive(:eligible?).and_return(true) }

  def enviar(conteudo, nome, tipo)
    post "#{base}/arquivos", params: { file: Rack::Test::UploadedFile.new(StringIO.new(conteudo), tipo, original_filename: nome) },
                             headers: admin.create_new_auth_token
  end

  it 'aceita planilha e devolve o signed_id que a pergunta usa', :aggregate_failures do
    enviar("nome,corretora\nKelly,Kcg\n", 'leads.csv', 'text/csv')

    expect(response).to have_http_status(:ok)
    signed_id = response.parsed_body['signed_id']
    expect(Autonomia::Guide::Arquivos.new(account: account).ler([signed_id]).first[:text]).to include('Kcg')
  end

  # O tipo sai do conteúdo, não do nome: uma imagem renomeada para .csv não passa.
  it 'recusa o que não sabe ler, pelo conteúdo', :aggregate_failures do
    png = "\x89PNG\r\n\x1A\n#{"\x00" * 32}".b
    enviar(png, 'foto.csv', 'text/csv')

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq(I18n.t('autonomia.guide.file.invalid_type'))
  end

  # O arquivo pode ter dado de cliente: passado o prazo do link, sai do armazenamento.
  it 'apaga o anexo depois que o link venceu, e só os anexos do Guia', :aggregate_failures do
    enviar("nome\nKelly\n", 'leads.csv', 'text/csv')
    outro = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('x'), filename: 'avatar.txt', content_type: 'text/plain')

    travel_to(2.days.from_now) { Autonomia::Guide::LimparArquivosJob.perform_now }

    expect(ActiveStorage::Blob.where(filename: 'leads.csv')).to be_empty
    expect(ActiveStorage::Blob.exists?(outro.id)).to be(true)
  end

  it 'leva os arquivos da conversa até o Guia, atravessando a fila' do
    expect do
      post "#{base}/chat", params: { message: 'resume a planilha', arquivos: %w[abc def] },
                           headers: admin.create_new_auth_token, as: :json
    end.to have_enqueued_job(Autonomia::Guide::ChatJob).with(anything, hash_including('arquivos' => %w[abc def]))
  end
end

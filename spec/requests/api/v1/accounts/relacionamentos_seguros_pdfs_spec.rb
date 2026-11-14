require 'rails_helper'

# E6 (#2899) — as rotas da leitura de PDF: anexar o PDF de um seguro e ver o que mudou (E6.2) e trazer seguros por PDFs
# (E6.3). Nenhuma chamada à IA: o job de leitura só é posto na fila, com o id do item, e os itens lidos são escritos
# como o Carteira::LerItem os deixa. Tudo fictício.
RSpec.describe 'Carteira de seguros: leitura de PDF', type: :request do
  include ActiveJob::TestHelper

  let(:account) { conta_com_carteira }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/relacionamentos" }
  let(:pessoa) { create(:contact, account: account, name: 'Pessoa Exemplo') }
  let(:seguro) { criar_apolice(pessoa, seguradora: 'Seguradora Exemplo', numero: 'EX-000111', fim_vigencia: Date.new(2027, 1, 1)) }
  let(:pdf) { Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf') }

  def ler_pdf(quem: admin)
    post "#{base}/seguros/#{seguro.id}/pdf/leitura", params: { arquivo: pdf }, headers: quem.create_new_auth_token
  end

  def enviar_pdfs(quem: admin, arquivos: [pdf, pdf])
    post "#{base}/trazer/seguros/leituras", params: { arquivos: arquivos }, headers: quem.create_new_auth_token
  end

  describe 'sem a leitura liberada (D4)' do
    it 'recusa ler e enviar com leitura_desligada, sem pôr nada na fila, e o resumo diz que não há leitura' do
      expect { ler_pdf }.not_to have_enqueued_job(Carteira::LeituraJob)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'leitura_desligada')

      expect { enviar_pdfs }.not_to have_enqueued_job(Carteira::LeituraJob)
      expect(response.parsed_body).to eq('error' => 'leitura_desligada')

      get "#{base}/seguros/resumo", headers: admin.create_new_auth_token
      expect(response.parsed_body['leituraDePdf']).to be(false)
    end
  end

  describe 'com a leitura liberada' do
    before { Carteira::Leitor::Liberado.ligar!(account) }

    def ler_e_responder(campos)
      ler_pdf
      leitura_id = response.parsed_body['leituraId']
      Carteira::LeituraItem.find_by!(leitura_id: leitura_id).update!(estado: 'lido', campos: campos)
      leitura_id
    end

    it 'lê o PDF anexado em segundo plano, só com o id do item na fila, e responde "lendo" sem cache' do
      expect { ler_pdf }.to have_enqueued_job(Carteira::LeituraJob).with(kind_of(Integer))
      expect(response).to have_http_status(:accepted)
      leitura_id = response.parsed_body['leituraId']

      get "#{base}/seguros/#{seguro.id}/pdf/leitura/#{leitura_id}", headers: admin.create_new_auth_token
      expect(response.parsed_body).to eq('leituraId' => leitura_id, 'estado' => 'lendo')
      expect(response.headers['Cache-Control']).to include('no-store')
    end

    it 'mostra o que mudou e guarda o PDF com os campos escolhidos' do
      leitura_id = ler_e_responder('seguradora' => 'Seguradora Exemplo', 'numero' => 'EX-000111', 'fim_vigencia' => '2027-02-01')

      get "#{base}/seguros/#{seguro.id}/pdf/leitura/#{leitura_id}", headers: admin.create_new_auth_token
      expect(response.parsed_body).to include('estado' => 'lido', 'outraApolice' => false)
      expect(response.parsed_body['mudancas']).to eq([{ 'campo' => 'termina', 'antes' => '2027-01-01', 'noPdf' => '2027-02-01',
                                                        'corrigidoAMao' => false, 'confira' => false, 'usar' => true }])

      post "#{base}/seguros/#{seguro.id}/pdf", params: { leituraId: leitura_id, usar: ['termina'] }, headers: admin.create_new_auth_token,
                                               as: :json
      expect(response).to have_http_status(:ok)
      expect(seguro.reload.fim_vigencia).to eq(Date.new(2027, 2, 1))
      expect(seguro.pdf).to be_attached
    end

    it 'não deixa quem não edita a pessoa ler o PDF, nem a pessoa de outra conta' do
      outra = conta_com_carteira
      de_fora = create(:user, account: outra, role: :administrator)

      ler_pdf(quem: de_fora)
      expect(response).to have_http_status(:unauthorized).or have_http_status(:not_found)
    end

    it 'recebe o lote de PDFs, põe um job por arquivo e responde o Conferir' do
      expect { enviar_pdfs }.to have_enqueued_job(Carteira::LeituraJob).exactly(2).times
      expect(response).to have_http_status(:created)
      id = response.parsed_body['id']

      get "#{base}/trazer/seguros/leituras/#{id}", headers: admin.create_new_auth_token
      expect(response.parsed_body).to include('estado' => 'lendo', 'total' => 2, 'lidos' => 0)

      get "#{base}/trazer/seguros/leituras", headers: admin.create_new_auth_token
      expect(response.parsed_body.pluck('id')).to eq([id])
    end

    it 'só deixa quem importa contatos enviar PDFs' do
      enviar_pdfs(quem: agente)

      expect(response).to have_http_status(:unauthorized)
    end

    it 'recusa lote sem arquivo e com arquivos demais' do
      expect { enviar_pdfs(arquivos: []) }.not_to have_enqueued_job(Carteira::LeituraJob)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('pedido_invalido').or eq('arquivo_obrigatorio')

      enviar_pdfs(arquivos: Array.new(Carteira::Trazer::Pdfs::Receber::MAXIMO + 1) { pdf })
      expect(response.parsed_body).to eq('error' => 'pedido_invalido')
    end
  end

  it 'não existe para a conta sem a carteira' do
    sem_carteira = create(:account)
    sem_carteira.enable_features!('relacionamentos_novo')
    quem = create(:user, account: sem_carteira, role: :administrator)

    caminho = "/api/v1/accounts/#{sem_carteira.id}/relacionamentos/trazer/seguros/leituras"
    post caminho, params: { arquivos: [pdf] }, headers: quem.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end
end

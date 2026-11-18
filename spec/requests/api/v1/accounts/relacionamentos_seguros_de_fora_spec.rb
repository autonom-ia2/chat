require 'rails_helper'

# E6.5 (#2899) — o seguro que a pessoa tem em outra corretora vira lembrete: os PDFs das conversas dela, ler um PDF,
# a leitura, guardar com o que foi conferido e apagar. Nenhuma chamada à IA: o job de leitura só é posto na fila, com o
# id do item, e o item lido é escrito como o Carteira::LerItem o deixa. Tudo fictício.
RSpec.describe 'Carteira de seguros: seguro de outra corretora', type: :request do
  include ActiveJob::TestHelper

  let(:account) { conta_com_carteira }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/relacionamentos" }
  let(:pessoa) { create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000031', email: 'marina@exemplo.test') }
  let(:pdf) { Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf') }
  let(:caminho) { "#{base}/pessoas/#{pessoa.id}/seguros_de_fora" }
  # O que o leitor deixa no item: o valor sem "R$" e o telefone do segurado ficam a confirmar.
  let(:lido) do
    { 'tipo' => 'auto', 'seguradora' => 'Seguradora Exemplo', 'fim_vigencia' => '2027-03-10', 'corretora' => 'Corretora Exemplo',
      'numero' => 'EX-000222', 'inicio_vigencia' => '2026-03-10', 'valor_centavos' => 125_000, 'bem' => 'Carro Exemplo 2020',
      'segurado_telefone' => '+5511900000099', 'segurado_email' => 'outro@exemplo.test' }
  end
  let(:duvidas) { %w[valor_centavos segurado_telefone segurado_email] }

  def ler(quem: admin, **corpo)
    corpo = { arquivo: pdf } if corpo.empty?
    post "#{caminho}/leitura", params: corpo, headers: quem.create_new_auth_token, as: (corpo.key?(:anexoId) ? :json : nil)
  end

  def ler_e_responder(campos: lido, estado: 'lido')
    ler
    leitura_id = response.parsed_body['leituraId']
    Carteira::LeituraItem.find_by!(leitura_id: leitura_id).update!(estado: estado, campos: campos, duvidas: duvidas)
    leitura_id
  end

  def guardar(leitura_id, quer: true, confirmados: [], quem: admin, **campos)
    formulario = { tipo: 'auto', seguradora: 'Seguradora Exemplo', termina: '2027-03-10', corretora: 'Corretora Exemplo' }.merge(campos)
    post caminho, params: { leituraId: leitura_id, querLembrete: quer, campos: formulario, confirmados: confirmados },
                  headers: quem.create_new_auth_token, as: :json
  end

  def pdf_na_conversa(nome: 'apolice-de-outra.pdf', privado: false, tipo: 'application/pdf')
    conversa = create(:conversation, account: account, contact: pessoa)
    mensagem = create(:message, account: account, inbox: conversa.inbox, conversation: conversa, message_type: :incoming, private: privado)
    anexo = mensagem.attachments.new(account_id: account.id, file_type: :file)
    anexo.file.attach(io: Rails.root.join('spec/assets/sample.pdf').open, filename: nome, content_type: tipo, identify: false)
    anexo.save!
    anexo
  end

  describe 'sem a leitura liberada (D4)' do
    it 'recusa tudo com leitura_desligada, sem guardar nem pôr nada na fila' do
      get "#{caminho}/arquivos", headers: admin.create_new_auth_token
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'leitura_desligada')

      expect { ler }.not_to have_enqueued_job(Carteira::LeituraJob)
      expect(response.parsed_body).to eq('error' => 'leitura_desligada')
      expect(Carteira::Leitura.count).to eq(0)
    end
  end

  describe 'com a leitura liberada' do
    before { Carteira::Leitor::Liberado.ligar!(account) }

    it 'lista só os PDFs trocados com a pessoa: a nota interna e a imagem não entram' do
      anexo = pdf_na_conversa
      pdf_na_conversa(nome: 'nota-interna.pdf', privado: true)
      pdf_na_conversa(nome: 'foto.png', tipo: 'image/png')

      get "#{caminho}/arquivos", headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([{ 'id' => anexo.id, 'nome' => 'apolice-de-outra.pdf', 'quando' => anexo.created_at.to_i }])
    end

    it 'lê o PDF enviado em segundo plano, só com o id do item na fila, com nome neutro e o contato da tela' do
      expect { ler }.to have_enqueued_job(Carteira::LeituraJob).with(kind_of(Integer))
      expect(response).to have_http_status(:accepted)

      leitura = Carteira::Leitura.find(response.parsed_body['leituraId'])
      item = leitura.itens.sole
      expect(leitura.totais).to eq('de_fora' => 1)
      expect(item).to have_attributes(contact_id: pessoa.id, apolice_id: nil, estado: 'lendo')
      expect(item.pdf.filename.to_s).to eq("seguro-de-fora-#{leitura.id}.pdf")

      get "#{caminho}/leitura/#{leitura.id}", headers: admin.create_new_auth_token
      expect(response.parsed_body).to eq('leituraId' => leitura.id, 'estado' => 'lendo')
      expect(response.headers['Cache-Control']).to include('no-store')
    end

    it 'lê um PDF que chegou na conversa copiando o arquivo: o da mensagem continua lá' do
      anexo = pdf_na_conversa

      expect { ler(anexoId: anexo.id) }.to have_enqueued_job(Carteira::LeituraJob)
      expect(response).to have_http_status(:accepted)

      item = Carteira::Leitura.find(response.parsed_body['leituraId']).itens.sole
      expect(item.pdf.blob_id).not_to eq(anexo.file.blob_id)
      expect(anexo.reload.file).to be_attached
    end

    it 'não lê o anexo de outra pessoa' do
      outra = create(:contact, account: account, name: 'Outra Exemplo')
      conversa = create(:conversation, account: account, contact: outra)
      anexo = create(:message, account: account, inbox: conversa.inbox, conversation: conversa).attachments.new(account_id: account.id,
                                                                                                                file_type: :file)
      anexo.file.attach(io: Rails.root.join('spec/assets/sample.pdf').open, filename: 'outra.pdf', content_type: 'application/pdf')
      anexo.save!

      expect { ler(anexoId: anexo.id) }.not_to have_enqueued_job(Carteira::LeituraJob)
      expect(response.parsed_body).to eq('error' => 'arquivo_obrigatorio')
    end

    it 'mostra o que foi lido: o telefone e o e-mail do PDF nunca aparecem, e o valor sem "R$" vem para conferir' do
      leitura_id = ler_e_responder

      get "#{caminho}/leitura/#{leitura_id}", headers: admin.create_new_auth_token

      expect(response.parsed_body).to eq(
        'leituraId' => leitura_id, 'estado' => 'lido',
        'lido' => { 'tipo' => 'auto', 'seguradora' => 'Seguradora Exemplo', 'termina' => '2027-03-10', 'corretora' => 'Corretora Exemplo' },
        'tambem' => [{ 'campo' => 'numero', 'valor' => 'EX-000222', 'confira' => false },
                     { 'campo' => 'comeca', 'valor' => '2026-03-10', 'confira' => false },
                     { 'campo' => 'valor', 'valor' => 1250.0, 'confira' => true },
                     { 'campo' => 'bem', 'valor' => 'Carro Exemplo 2020', 'confira' => false }]
      )
      expect(response.body).not_to include('+5511900000099', 'outro@exemplo.test')
    end

    it 'o PDF que não é apólice responde a recusa, e a leitura que não existe responde leitura_expirou' do
      leitura_id = ler_e_responder(campos: {}, estado: 'recusado')

      get "#{caminho}/leitura/#{leitura_id}", headers: admin.create_new_auth_token
      expect(response.parsed_body).to eq('leituraId' => leitura_id, 'estado' => 'recusado', 'recusa' => 'nao_e_apolice')

      get "#{caminho}/leitura/0", headers: admin.create_new_auth_token
      expect(response.parsed_body).to eq('error' => 'leitura_expirou')
    end

    it 'guarda com o lembrete: de fora, da pessoa da tela, com a corretora, o PDF e a história; a leitura sai' do
      leitura_id = ler_e_responder

      guardar(leitura_id)

      expect(response).to have_http_status(:created)
      seguro = pessoa.apolices.sole
      expect(seguro).to have_attributes(de_fora: true, corretora_de_fora: 'Corretora Exemplo', tipo: 'auto', seguradora: 'Seguradora Exemplo',
                                        fim_vigencia: Date.new(2027, 3, 10), inicio_vigencia: Date.new(2026, 3, 10), numero: 'EX-000222',
                                        bem: 'Carro Exemplo 2020', valor_centavos: nil, origem: 'pdf', lembrete_aceito_em: be_present)
      expect(seguro.pdf).to be_attached
      expect(seguro.eventos.pluck(:tipo)).to contain_exactly('chegou_de_fora', 'pdf_anexado')
      expect(seguro.eventos.find_by(tipo: 'chegou_de_fora').valores).to eq('lembrete' => true)
      expect(response.parsed_body).to include('id' => seguro.id, 'deFora' => true, 'corretora' => 'Corretora Exemplo')
      expect(Carteira::Leitura.exists?(leitura_id)).to be(false)
    end

    it 'o telefone e o e-mail do PDF não vão para o contato (P5)' do
      guardar(ler_e_responder)

      expect(pessoa.reload).to have_attributes(phone_number: '+5511900000031', email: 'marina@exemplo.test')
    end

    it 'sem o lembrete fica só guardado; o valor a conferir entra só quando a pessoa diz que está certo' do
      guardar(ler_e_responder, quer: false, confirmados: ['valor'])

      expect(response).to have_http_status(:created)
      seguro = pessoa.apolices.sole
      expect(seguro).to have_attributes(de_fora: true, lembrete_aceito_em: nil, valor_centavos: 125_000)
      expect(response.parsed_body['lembreteAceitoEm']).to be_nil
    end

    it 'o que a pessoa escreveu vale sobre o que foi lido, e o mesmo seguro não entra duas vezes (P4)' do
      guardar(ler_e_responder, seguradora: 'Seguradora Escrita', termina: '2027-04-01', corretora: '')
      expect(pessoa.apolices.sole).to have_attributes(seguradora: 'Seguradora Escrita', fim_vigencia: Date.new(2027, 4, 1), corretora_de_fora: nil)

      guardar(ler_e_responder, seguradora: 'Seguradora Escrita', termina: '2027-04-01')
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'seguro_de_fora_repetido')
      expect(pessoa.apolices.count).to eq(1)
    end

    it 'recusa o que falta, sem guardar: o tipo, a seguradora, quando termina e a resposta do lembrete' do
      leitura_id = ler_e_responder

      { { tipo: '' } => 'falta_tipo', { tipo: 'barco' } => 'tipo_desconhecido', { seguradora: ' ' } => 'falta_seguradora',
        { termina: '' } => 'falta_termina', { termina: '2027-02-31' } => 'data_invalida',
        { seguradora: 'S' * 256 } => 'texto_longo' }.each do |campos, codigo|
        guardar(leitura_id, **campos)
        expect(response.parsed_body).to eq({ 'error' => codigo }), campos.inspect
      end

      guardar(leitura_id, quer: nil)
      expect(response.parsed_body).to eq('error' => 'pedido_invalido')
      expect(pessoa.apolices.count).to eq(0)
    end

    it 'não deixa guardar com a leitura de outra pessoa' do
      leitura_id = ler_e_responder
      outra = create(:contact, account: account, name: 'Outra Exemplo')

      post "#{base}/pessoas/#{outra.id}/seguros_de_fora",
           params: { leituraId: leitura_id, querLembrete: true, campos: { tipo: 'auto', seguradora: 'Seguradora Exemplo', termina: '2027-03-10' } },
           headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body).to eq('error' => 'leitura_expirou')
      expect(Carteira::Apolice.count).to eq(0)
    end

    it 'não deixa a pessoa de outra conta ler' do
      de_fora = create(:user, account: conta_com_carteira, role: :administrator)

      expect { ler(quem: de_fora) }.not_to have_enqueued_job(Carteira::LeituraJob)
      expect(response).to have_http_status(:unauthorized).or have_http_status(:not_found)
    end
  end

  describe 'apagar (DELETE seguros/:id)' do
    it 'apaga o seguro de outra corretora' do
      seguro = criar_apolice(pessoa, seguradora: 'Seguradora Exemplo', fim_vigencia: Date.new(2027, 3, 10), de_fora: true)

      delete "#{base}/seguros/#{seguro.id}", headers: admin.create_new_auth_token

      expect(response).to have_http_status(:no_content)
      expect(Carteira::Apolice.exists?(seguro.id)).to be(false)
    end

    it 'apaga o seguro que já tinha card de renovação e deixa o card arquivado' do
      ajustes = escolher_funil_de_renovacao(account, user: admin)
      seguro = criar_apolice(pessoa, seguradora: 'Seguradora Exemplo', fim_vigencia: Date.new(2027, 3, 10), de_fora: true,
                                     lembrete_aceito_em: Time.current)
      card = por_em_renovacao(seguro, ajustes)

      delete "#{base}/seguros/#{seguro.id}", headers: admin.create_new_auth_token

      expect(response).to have_http_status(:no_content)
      expect(Carteira::Apolice.exists?(seguro.id)).to be(false)
      expect(card.reload).to be_archived
    end

    it 'não apaga o seguro da carteira da corretora: ele se cancela, não some' do
      seguro = criar_apolice(pessoa, seguradora: 'Seguradora Exemplo', numero: 'EX-000333', fim_vigencia: Date.new(2027, 3, 10))

      delete "#{base}/seguros/#{seguro.id}", headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'nao_e_de_fora')
      expect(Carteira::Apolice.exists?(seguro.id)).to be(true)
    end
  end

  it 'não existe para a conta sem a carteira' do
    sem_carteira = create(:account)
    quem = create(:user, account: sem_carteira, role: :administrator)
    alguem = create(:contact, account: sem_carteira)

    get "/api/v1/accounts/#{sem_carteira.id}/relacionamentos/pessoas/#{alguem.id}/seguros_de_fora/arquivos", headers: quem.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end
end

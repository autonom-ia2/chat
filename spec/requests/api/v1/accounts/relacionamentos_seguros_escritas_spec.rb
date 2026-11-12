require 'rails_helper'

# E4 (#2897) — as escritas da gaveta do seguro: corrigir, marcar como cancelado, voltar a ativo, guardar e tirar o PDF.
# Cada uma devolve o seguro como ficou e deixa a história dela. A recusa é um código em `error`, e o corpo nunca repete
# o que foi mandado. A metade de função personalizada fica em spec/enterprise/requests/relacionamentos/seguros_spec.rb.
RSpec.describe 'Carteira de seguros: escritas', type: :request do
  # Meio-dia em São Paulo: para a conta, hoje é 12/11/2026.
  let(:agora) { Time.utc(2026, 11, 12, 15) }
  let(:account) { conta_com_carteira(reporting_timezone: 'America/Sao_Paulo') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/relacionamentos" }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023', contact_type: :customer) }
  let(:seguro) do
    criar_apolice(marina, numero: 'EX-001234', inicio_vigencia: Date.new(2025, 12, 16), fim_vigencia: Date.new(2026, 12, 16),
                          valor_centavos: 341_000, bem: 'Carro Exemplo 2022')
  end
  let(:guardado) { seguro.attributes.except('updated_at') }
  let(:pdf_de_exemplo) { Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf') }

  before do
    travel_to(agora)
    guardado
  end

  def cabecalhos(quem)
    quem.create_new_auth_token
  end

  def corrigir(dados, quem: admin, id: seguro.id)
    patch "#{base}/seguros/#{id}", params: dados, headers: cabecalhos(quem), as: :json
  end

  def acao(nome, quem: admin, id: seguro.id, **dados)
    post "#{base}/seguros/#{id}/#{nome}", params: dados, headers: cabecalhos(quem), as: :json
  end

  def guardar_pdf(arquivo, quem: admin, id: seguro.id)
    post "#{base}/seguros/#{id}/pdf", params: { arquivo: arquivo }.compact, headers: cabecalhos(quem)
  end

  def tirar_pdf(quem: admin, id: seguro.id)
    delete "#{base}/seguros/#{id}/pdf", headers: cabecalhos(quem)
  end

  def ler(caminho, quem: admin)
    get "#{base}/#{caminho}", headers: cabecalhos(quem)
  end

  def eventos
    seguro.eventos.order(:id).pluck(:tipo)
  end

  def nao_mudou
    seguro.reload.attributes.except('updated_at') == guardado && eventos.empty?
  end

  # Cada escrita, para os exemplos que valem para todas.
  def escritas(quem: admin, id: seguro.id)
    { 'corrigir' => -> { corrigir({ bem: 'Carro Exemplo 2023' }, quem: quem, id: id) },
      'cancelar' => -> { acao('cancelar', quem: quem, id: id) },
      'voltar a ativo' => -> { acao('voltar_a_ativo', quem: quem, id: id) },
      'guardar o PDF' => -> { guardar_pdf(pdf_de_exemplo, quem: quem, id: id) },
      'tirar o PDF' => -> { tirar_pdf(quem: quem, id: id) } }
  end

  describe 'em todas as escritas' do
    it 'responde 401 sem login e não muda nada' do
      [[:patch, "seguros/#{seguro.id}"], [:post, "seguros/#{seguro.id}/cancelar"], [:post, "seguros/#{seguro.id}/voltar_a_ativo"],
       [:post, "seguros/#{seguro.id}/pdf"], [:delete, "seguros/#{seguro.id}/pdf"]].each do |verbo, caminho|
        send(verbo, "#{base}/#{caminho}")

        expect(response).to have_http_status(:unauthorized), caminho
      end
      expect(nao_mudou).to be(true)
    end

    it 'responde 404 com a chave da carteira desligada e não muda nada' do
      account.disable_features!('carteira_seguros')

      escritas.each do |nome, pedir|
        pedir.call

        expect(response).to have_http_status(:not_found), nome
      end
      expect(nao_mudou).to be(true)
    end

    it 'responde 404 para o seguro de outra conta e não muda nada nele' do
      outra = conta_com_carteira
      de_fora = guardar_pdf_na(criar_apolice(create(:contact, account: outra), numero: 'EX-777777', bem: 'Casa Exemplo'))
      antes = de_fora.attributes

      escritas(id: de_fora.id).each do |nome, pedir|
        pedir.call

        expect(response).to have_http_status(:not_found), nome
      end
      expect([de_fora.reload.attributes, de_fora.eventos.count, de_fora.pdf.attached?]).to eq([antes, 0, true])
    end

    it 'atende o agente comum, como editar o contato de hoje' do
      corrigir({ bem: 'Carro Exemplo 2023' }, quem: agente)

      expect(response).to have_http_status(:ok)
      expect(seguro.reload.bem).to eq('Carro Exemplo 2023')
    end
  end

  describe 'corrigir' do
    it 'grava só o que mudou, deixa na história o antes e o depois em valor de banco e marca os campos como corrigidos à mão' do
      corrigir({ valor: 3500.5, termina: '2026-12-20', bem: 'Carro Exemplo 2023', tipo: 'auto' })

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('id' => seguro.id, 'valor' => 3500.5, 'termina' => '2026-12-20', 'bem' => 'Carro Exemplo 2023',
                                              'comeca' => '2025-12-16', 'numero' => 'EX-001234', 'corrigidoAMao' => %w[termina valor bem])
      expect(seguro.reload).to have_attributes(valor_centavos: 350_050, fim_vigencia: Date.new(2026, 12, 20), bem: 'Carro Exemplo 2023',
                                               corrigido_a_mao: %w[termina valor bem])
      expect(seguro.eventos.sole).to have_attributes(
        tipo: 'corrigido', quando: agora, user_id: admin.id, valores: { 'campos' => %w[termina valor bem] },
        mudancas: [{ 'campo' => 'termina', 'antes' => '2026-12-16', 'depois' => '2026-12-20' },
                   { 'campo' => 'valor', 'antes' => 341_000, 'depois' => 350_050 },
                   { 'campo' => 'bem', 'antes' => 'Carro Exemplo 2022', 'depois' => 'Carro Exemplo 2023' }]
      )
    end

    it 'soma os campos corrigidos aos que já estavam marcados, sem repetir' do
      seguro.update!(corrigido_a_mao: %w[valor])

      corrigir({ valor: '3410.55', bem: 'Carro Exemplo 2023' })

      expect(seguro.reload).to have_attributes(valor_centavos: 341_055, corrigido_a_mao: %w[valor bem])
    end

    it 'mandar o mesmo valor não é correção: não grava, não marca e não entra na história' do
      corrigir({ valor: 3410, termina: '2026-12-16', bem: 'Carro Exemplo 2022', numero: 'EX-001234', seguradora: 'Seguradora Exemplo',
                 comeca: '2025-12-16', tipo: 'auto' })

      expect(response).to have_http_status(:ok)
      expect(nao_mudou).to be(true)
    end

    it 'refaz a forma de comparação quando a seguradora ou o número mudam' do
      corrigir({ seguradora: ' Seguradora Exemplo S.A. ', numero: 'ex 001234-9' })

      expect(seguro.reload).to have_attributes(seguradora: 'Seguradora Exemplo S.A.', seguradora_chave: 'seguradoraexemplosa',
                                               numero: 'ex 001234-9', numero_chave: 'EX0012349')
    end

    it 'aceita tirar o valor, o começo da vigência e o bem' do
      corrigir({ valor: nil, comeca: nil, bem: ' ' })

      expect(response.parsed_body).to include('valor' => nil, 'comeca' => nil, 'bem' => nil)
      expect(seguro.reload).to have_attributes(valor_centavos: nil, inicio_vigencia: nil, bem: nil, corrigido_a_mao: %w[comeca valor bem])
    end

    it 'recusa com o código de cada caso, sem repetir o que foi mandado e sem gravar nada' do
      recusas = {
        'tipo_desconhecido' => [{ tipo: 'moto' }, { tipo: nil }],
        'falta_seguradora' => [{ seguradora: ' ' }, { seguradora: '---' }, { seguradora: nil }],
        'falta_numero' => [{ numero: '' }, { numero: '.-/' }],
        'falta_termina' => [{ termina: '' }, { termina: nil }],
        'termina_antes' => [{ termina: '2025-01-01' }, { comeca: '2027-01-01' }, { comeca: '2026-06-01', termina: '2026-05-31' }],
        'data_invalida' => [{ comeca: '12/11/2026' }, { termina: '2026-02-30' }, { termina: '2026-2-3' }, { termina: 'amanhã' },
                            { termina: '99999999-01-01' }, { comeca: '0026-11-12' }],
        'valor_invalido' => [{ valor: 'três mil' }, { valor: -1 }, { valor: '10.999' }, { valor: 'NaN' }, { valor: '3.410,00' }]
      }

      recusas.each do |codigo, pedidos|
        pedidos.each do |pedido|
          corrigir(pedido.merge(bem: 'Carro Exemplo 2023'))

          expect(response).to have_http_status(:unprocessable_entity), "#{codigo} #{pedido}"
          expect(response.parsed_body).to eq('error' => codigo), pedido.to_s
        end
      end
      expect(nao_mudou).to be(true)
    end

    it 'recusa com apolice_repetida a que ficaria igual a outra da conta, e a conta segue usável depois da recusa' do
      criar_apolice(marina, numero: 'EX-009999', fim_vigencia: seguro.fim_vigencia)

      corrigir({ numero: 'ex 009.999' })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'apolice_repetida')
      expect(nao_mudou).to be(true)

      corrigir({ numero: 'EX-001235' })

      expect(response).to have_http_status(:ok)
      expect(seguro.reload.numero_chave).to eq('EX001235')
    end

    it 'a mesma apólice em outra conta não atrapalha' do
      outra = conta_com_carteira
      criar_apolice(create(:contact, account: outra), numero: 'EX-009999', fim_vigencia: seguro.fim_vigencia)

      corrigir({ numero: 'EX-009999' })

      expect(response).to have_http_status(:ok)
    end

    it 'responde 422, sem repetir o que foi mandado, para campo que a correção não conhece ou que chega em formato errado' do
      [{ placa: 'EXE0X00' }, { valor: [3410] }, { bem: { nome: 'Carro Exemplo 2023' } }, { contact_id: 1 }, { cancelado_em: nil }].each do |pedido|
        corrigir(pedido)

        expect(response).to have_http_status(:unprocessable_entity), pedido.to_s
        expect(response.parsed_body).to eq('error' => 'pedido_invalido'), pedido.to_s
      end
      expect(nao_mudou).to be(true)
    end
  end

  describe 'cancelar e voltar a ativo' do
    it 'cancela, guarda quem fez, tira o seguro dos grupos de vencimento e recusa cancelar de novo' do
      acao('cancelar', quem: agente)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('selo' => 'cancelado', 'canceladoEm' => agora.to_i, 'dias' => 34)
      expect(seguro.eventos.sole).to have_attributes(tipo: 'cancelado', user_id: agente.id, quando: agora)
      ler('seguros/contagens')
      expect(response.parsed_body).to include('todos' => 1, 'vence_90_dias' => 0)

      acao('cancelar')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'ja_cancelado')
      expect(eventos).to eq(%w[cancelado])
    end

    it 'volta a ativo com o selo que a data manda, e recusa voltar o que não está cancelado' do
      acao('voltar_a_ativo')
      expect([response.status, response.parsed_body]).to eq([422, { 'error' => 'nao_cancelado' }])

      acao('cancelar')
      acao('voltar_a_ativo')

      expect(response.parsed_body).to include('selo' => 'ativo', 'canceladoEm' => nil)
      expect(eventos).to eq(%w[cancelado voltou_a_ativo])

      seguro.update!(inicio_vigencia: nil, fim_vigencia: Date.new(2026, 11, 1))
      acao('cancelar')
      acao('voltar_a_ativo')

      expect(response.parsed_body).to include('selo' => 'vencido', 'dias' => -11)
    end

    it 'responde 422 para qualquer campo no corpo: as duas ações não recebem nada' do
      %w[cancelar voltar_a_ativo].each do |nome|
        acao(nome, motivo: 'vendeu o carro')

        expect([response.status, response.parsed_body]).to eq([422, { 'error' => 'pedido_invalido' }]), nome
      end
      expect(nao_mudou).to be(true)
    end
  end

  describe 'o PDF da apólice' do
    it 'guarda o arquivo com um nome neutro, marca o seguro com PDF e deixa na história' do
      guardar_pdf(pdf_de_exemplo, quem: agente)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('id' => seguro.id, 'temPdf' => true)
      expect(seguro.reload.pdf.blob.content_type).to eq('application/pdf')
      expect(seguro.pdf.blob.filename.to_s).to eq("apolice-#{seguro.id}.pdf")
      expect(seguro.eventos.sole).to have_attributes(tipo: 'pdf_anexado', user_id: agente.id, quando: agora)
    end

    it 'dá um link que abre o arquivo, não fica em cache e deixa de valer depois de um minuto' do
      guardar_pdf(pdf_de_exemplo)

      ler("seguros/#{seguro.id}/pdf", quem: agente)

      expect(response).to have_http_status(:ok)
      expect(response.headers['Cache-Control']).to include('no-store')
      link = URI.parse(response.parsed_body['url'])
      get link.request_uri
      expect([response.status, response.body.start_with?('%PDF')]).to eq([200, true])

      travel_to(agora + 61.seconds)
      get link.request_uri

      expect(response).to have_http_status(:not_found)
    end

    it 'guardar outro PDF troca o anterior: o seguro fica com um arquivo só' do
      guardar_pdf(pdf_de_exemplo)
      primeiro = seguro.reload.pdf.blob.id

      guardar_pdf(Rack::Test::UploadedFile.new(StringIO.new('%PDF-1.4 segunda via'), 'application/pdf', original_filename: 'segunda-via.pdf'))

      anexos = ActiveStorage::Attachment.where(record_type: 'Carteira::Apolice', record_id: seguro.id)
      expect(anexos.count).to eq(1)
      expect(anexos.sole.blob_id).not_to eq(primeiro)
      expect(eventos).to eq(%w[pdf_anexado pdf_anexado])
    end

    it 'recusa pedido sem arquivo, arquivo que não é PDF por dentro e arquivo acima do limite de anexo da instalação' do
      allow(GlobalConfigService).to receive(:load).and_call_original
      allow(GlobalConfigService).to receive(:load).with('MAXIMUM_FILE_UPLOAD_SIZE', 40).and_return(1)
      foto_com_nome_de_pdf = Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/avatar.png'), 'application/pdf',
                                                          original_filename: 'apolice-da-marina.pdf')
      grande = Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4\n#{'0' * 1.megabyte}"), 'application/pdf',
                                            original_filename: 'apolice-grande.pdf')
      recusas = { 'arquivo_obrigatorio' => [nil, 'apolice-da-marina.pdf'], 'tipo' => [foto_com_nome_de_pdf], 'arquivo_grande' => [grande] }

      recusas.each do |codigo, arquivos|
        arquivos.each do |arquivo|
          guardar_pdf(arquivo)

          expect(response).to have_http_status(:unprocessable_entity), codigo
          expect(response.parsed_body).to eq('error' => codigo)
        end
      end
      expect(seguro.reload.pdf).not_to be_attached
      expect(nao_mudou).to be(true)
    end

    it 'tirar o PDF manda o arquivo para a limpeza, o seguro volta a ficar sem PDF e a história guarda quem tirou' do
      seguro.eventos.create!(tipo: 'chegou_planilha', quando: agora - 1.day)
      guardar_pdf(pdf_de_exemplo)

      expect { tirar_pdf(quem: agente) }.to have_enqueued_job(ActiveStorage::PurgeJob)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('id' => seguro.id, 'temPdf' => false)
      expect(seguro.reload.pdf).not_to be_attached
      expect(eventos).to eq(%w[chegou_planilha pdf_anexado pdf_tirado])
      expect(seguro.eventos.order(:id).last).to have_attributes(user_id: agente.id, quando: agora)
    end

    it 'sem PDF guardado, pedir o link e tirar respondem sem_pdf' do
      ler("seguros/#{seguro.id}/pdf")
      expect([response.status, response.parsed_body]).to eq([422, { 'error' => 'sem_pdf' }])

      tirar_pdf
      expect([response.status, response.parsed_body]).to eq([422, { 'error' => 'sem_pdf' }])
    end
  end
end

require 'rails_helper'

# #2896 — "Trazer minha lista" (Fatia 2), a conferência: as linhas que precisam da pessoa. Consertar, deixar de fora,
# voltar atrás, e o que continua valendo quando a planilha é lida de novo.
RSpec.describe 'Trazer minha lista: as linhas que precisam da pessoa (Relacionamentos)', :aggregate_failures, type: :request do
  include_context 'with trazer conferencia'

  let(:valores_da_planilha) { %w[11987650001 11987650002 11987650004 11987650005 ana.albuquerino davi.dornelino 2345-678] }

  it 'conserta o telefone: a linha fica guardada, com o número como vai ser gravado, e o valor fica só no arquivo dos consertos' do
    importacao = ler_planilha(com_problemas)

    consertar(importacao, 4, valor: '(11) 98765-0004')

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      'problema' => { 'linha' => 4, 'tipo' => 'telefone', 'nome' => 'Carla Carvalhedo', 'valor' => '(11) 2345-678', 'estado' => 'guardado',
                      'corrigido' => '+5511987650004' },
      'entram' => 3
    )
    expect(importacao.reload.options['trazer']).to eq({})
    expect(importacao).to have_attributes(status: 'ready_to_confirm', valid_rows: 2, invalid_rows: 5)
    expect(importacao.campaign_import_rows.find_by!(row_number: 4)).to be_status_invalid
    expect(consertos(importacao)).to eq(
      4 => ['telefone', { 'phone' => '(11) 98765-0004' }, { 'name' => 'Carla Carvalhedo', 'phone_number' => '+5511987650004', 'email' => nil }]
    )
    # O arquivo conferido só muda na hora de trazer.
    expect(conferido(importacao).pluck(:row_number)).to eq([2, 3])
    linhas = importacao.campaign_import_rows.map { |linha| linha.attributes.except('raw_name') }
    guardado = [importacao.options, importacao.validation_summary, linhas]
    expect(guardado.to_json).not_to include('987650004', '98765-0004', *valores_da_planilha)
  end

  it 'conserta o e-mail, o nome e a linha sem contato (com telefone ou com e-mail)' do
    importacao = ler_planilha(com_problemas)

    consertar(importacao, 5, valor: ' Davi.Dornelino@Exemplo.com.br ')
    expect(response.parsed_body['problema']).to include('linha' => 5, 'tipo' => 'email', 'estado' => 'guardado',
                                                        'corrigido' => 'davi.dornelino@exemplo.com.br')
    consertar(importacao, 6, valor: '  Fabio   Ferreirinho ')
    expect(response.parsed_body['problema']).to include('linha' => 6, 'tipo' => 'nome', 'nome' => '', 'contato' => '11987650005',
                                                        'estado' => 'guardado', 'corrigido' => 'Fabio Ferreirinho')
    consertar(importacao, 7, valor: '11 98765-0007')
    expect(response.parsed_body['problema'])
      .to include('linha' => 7, 'tipo' => 'sem_contato', 'estado' => 'guardado', 'corrigido' => '+5511987650007')
    consertar(importacao, 7, valor: 'elisa@exemplo.com.br')
    expect(response.parsed_body['problema']).to include('linha' => 7, 'estado' => 'guardado', 'corrigido' => 'elisa@exemplo.com.br')

    # Na leitura seguinte a tela continua vendo o que foi guardado, lido do arquivo dos consertos.
    expect(ler(importacao)['problemas'].to_h { |problema| [problema['linha'], problema['corrigido']] }).to eq(
      4 => nil, 5 => 'davi.dornelino@exemplo.com.br', 6 => 'Fabio Ferreirinho', 7 => 'elisa@exemplo.com.br', 8 => nil
    )
    expect(response.parsed_body['resumo']).to eq('total' => 7, 'novas' => 2, 'completadas' => 0, 'comProblema' => 5, 'juntadas' => 0,
                                                 'entram' => 5)
  end

  it 'recusa o valor que não vale, com o motivo em código e sem guardar nada' do
    importacao = ler_planilha(com_problemas)
    recusas = {
      [4, '(11) 2345-6789'] => 'invalid_brazilian_mobile_number', [4, ''] => 'blank_phone_number', [4, nil] => 'blank_phone_number',
      [4, '=1+1'] => 'formula_phone_number', [5, 'davi.exemplo.com.br'] => 'invalid_email', [5, ' '] => 'blank_email',
      [6, ''] => 'blank_name', [6, '=SOMA(A1)'] => 'formula_detected', [7, ''] => 'missing_contact',
      [7, '123'] => 'invalid_brazilian_mobile_number', [7, 'elisa@'] => 'invalid_email'
    }

    recusas.each do |(linha, valor), motivo|
      consertar(importacao, linha, valor: valor)

      expect(response).to have_http_status(:unprocessable_entity), [linha, valor].inspect
      expect(response.parsed_body).to eq('error' => 'valor_invalido', 'motivo' => motivo), [linha, valor].inspect
    end
    expect(importacao.reload.options['trazer']).to eq({})
    expect(importacao.consertos).not_to be_attached
    expect(conferido(importacao).pluck(:row_number)).to eq([2, 3])
  end

  it 'recusa o valor longo demais' do
    importacao = ler_planilha(com_problemas)

    consertar(importacao, 4, valor: '1' * 256)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'valor_invalido', 'motivo' => 'muito_longo')
  end

  it 'guarda o conserto que vale e mostra o problema que sobrou na linha; só recusa o valor digitado que não vale' do
    # Linha 3: telefone errado e sem nome. Linha 4: telefone errado e uma fórmula na empresa.
    linhas = ['Nome;Celular;E-mail;Empresa', 'Ana Albuquerino;11987650001;;', ';(11) 2345-678;;', 'Caio Camargo;(11) 2345-679;;=SOMA(A1)']
    importacao = ler_planilha("#{linhas.join("\n")}\n")
    # A linha 4 tem fórmula na empresa, que a tela não conserta: aparece direto como `formula`, sem pedir antes o
    # telefone, que não adiantaria consertar.
    expect(ler(importacao)['problemas'].pluck('linha', 'tipo')).to eq([[3, 'telefone'], [4, 'formula']])

    consertar(importacao, 3, valor: '11987650003')
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      'problema' => { 'linha' => 3, 'tipo' => 'nome', 'nome' => '', 'valor' => '', 'contato' => '11987650003', 'estado' => 'aberto',
                      'motivo' => 'blank_name' },
      'entram' => 1
    )
    expect(estados(importacao)).to eq(3 => 'aberto', 4 => 'aberto')

    reabrir(importacao, 3)
    expect(response.parsed_body['problema']).to include('tipo' => 'telefone', 'valor' => '(11) 2345-678', 'estado' => 'aberto')
    consertar(importacao, 3, valor: '11987650003')
    consertar(importacao, 3, valor: ' ')
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'valor_invalido', 'motivo' => 'blank_name')
    consertar(importacao, 3, valor: 'Bruno Brandolim')
    expect(response.parsed_body['problema']).to include('linha' => 3, 'tipo' => 'nome', 'estado' => 'guardado', 'corrigido' => 'Bruno Brandolim')

    # Linha 4: nenhum valor é aceito, nem o telefone bom. Ela só pode ficar de fora.
    consertar(importacao, 4, valor: '11987650004')
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'valor_invalido', 'motivo' => 'formula_detected')
    expect(estados(importacao)).to eq(3 => 'guardado', 4 => 'aberto')

    trazer(importacao)
    gravar_a_lista
    expect(account.contacts.pluck(:name, :phone_number))
      .to contain_exactly(['Ana Albuquerino', '+5511987650001'], ['Bruno Brandolim', '+5511987650003'])
  end

  it 'diz o motivo de cada problema aberto, em código; a linha guardada, a deixada de fora e a repetida não têm motivo' do
    importacao = ler_planilha(com_problemas)
    motivos = -> { ler(importacao)['problemas'].to_h { |problema| [problema['linha'], problema['motivo']] } }

    expect(motivos.call).to eq(4 => 'invalid_brazilian_mobile_number', 5 => 'invalid_email', 6 => 'blank_name', 7 => 'missing_contact', 8 => nil)
    expect(response.parsed_body['problemas'].last).not_to have_key('motivo')

    consertar(importacao, 4, valor: '11987650004')
    expect(response.parsed_body['problema']).not_to have_key('motivo')
    deixar_de_fora(importacao, 5)
    expect(response.parsed_body['problema']).not_to have_key('motivo')
    expect(motivos.call).to eq(4 => nil, 5 => nil, 6 => 'blank_name', 7 => 'missing_contact', 8 => nil)

    reabrir(importacao, 5)
    expect(response.parsed_body['problema']).to eq('linha' => 5, 'tipo' => 'email', 'nome' => 'Davi Dornelino', 'estado' => 'aberto',
                                                   'valor' => 'davi.dornelino.exemplo.com.br', 'motivo' => 'invalid_email')
  end

  it 'a célula que parece fórmula: o problema é do campo dela, e a da empresa, que a tela não conserta, é do tipo "formula"' do
    # Linha 3: fórmula no nome. 4: no telefone (o e-mail vale). 5: no e-mail (o telefone vale). 6: na empresa.
    # 7: na empresa e sem nome.
    linhas = ['Nome;Celular;E-mail;Empresa', 'Ana Albuquerino;11987650001;;Padaria Bom Dia', '=SOMA(A1);11987650002;;',
              'Caio Camargo;=1+1;caio.camargo@exemplo.com.br;', 'Davi Dornelino;11987650004;=SOMA(C1);', 'Elisa Esteveira;11987650005;;=SOMA(B2)',
              ';11987650006;;=SOMA(B3)']
    importacao = ler_planilha("#{linhas.join("\n")}\n")

    problemas = ler(importacao)['problemas']
    expect(problemas.map { |problema| problema.slice('linha', 'tipo', 'motivo', 'valor') }).to eq(
      [{ 'linha' => 3, 'tipo' => 'nome', 'motivo' => 'formula_detected', 'valor' => '=SOMA(A1)' },
       { 'linha' => 4, 'tipo' => 'telefone', 'motivo' => 'formula_detected', 'valor' => '=1+1' },
       { 'linha' => 5, 'tipo' => 'email', 'motivo' => 'formula_detected', 'valor' => '=SOMA(C1)' },
       { 'linha' => 6, 'tipo' => 'formula', 'motivo' => 'formula_detected' },
       # Sem nome e com fórmula na empresa: direto `formula`, porque escrever o nome não adiantaria.
       { 'linha' => 7, 'tipo' => 'formula', 'motivo' => 'formula_detected' }]
    )
    da_empresa = { 'linha' => 6, 'tipo' => 'formula', 'campo' => 'empresa', 'nome' => 'Elisa Esteveira', 'estado' => 'aberto',
                   'motivo' => 'formula_detected' }
    expect(problemas[3]).to eq(da_empresa)

    # A tela não conserta a empresa: o valor é recusado; deixar de fora e voltar atrás funcionam.
    consertar(importacao, 6, valor: 'Padaria Bom Dia')
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'valor_invalido', 'motivo' => 'formula_detected')
    expect(importacao.reload.consertos).not_to be_attached
    deixar_de_fora(importacao, 6)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('problema' => da_empresa.except('motivo').merge('estado' => 'deixado'), 'entram' => 1)
    reabrir(importacao, 6)
    expect(response.parsed_body).to eq('problema' => da_empresa, 'entram' => 1)

    consertar(importacao, 7, valor: 'Fabio Ferreirinho')
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'valor_invalido', 'motivo' => 'formula_detected')

    # A fórmula no nome, no telefone e no e-mail a pessoa conserta.
    consertar(importacao, 3, valor: 'Bruno Brandolim')
    expect(response.parsed_body['problema']).to include('linha' => 3, 'tipo' => 'nome', 'estado' => 'guardado', 'corrigido' => 'Bruno Brandolim')
    consertar(importacao, 4, valor: '11987650003')
    expect(response.parsed_body['problema']).to include('linha' => 4, 'tipo' => 'telefone', 'estado' => 'guardado')
    consertar(importacao, 5, valor: 'davi.dornelino@exemplo.com.br')
    expect(response.parsed_body['problema']).to include('linha' => 5, 'tipo' => 'email', 'estado' => 'guardado')

    # Sem o arquivo das linhas com problema, a fórmula na empresa continua sendo dita: a empresa está na linha.
    importacao.linhas_com_problema.purge
    expect(ler(importacao)['problemas'][3]).to eq(da_empresa)

    trazer(importacao)
    gravar_a_lista
    expect(account.contacts.pluck(:name)).to contain_exactly('Ana Albuquerino', 'Bruno Brandolim', 'Caio Camargo', 'Davi Dornelino')
  end

  it 'mostra a linha guardada e mexe nas linhas sem abrir o arquivo conferido inteiro nem a planilha original' do
    importacao = ler_planilha(com_problemas)
    consertar(importacao, 4, valor: '11987650004')
    original = importacao.original_file.blob.key
    arquivo_conferido = importacao.reload.normalized_csv.blob.key
    allow(ActiveStorage::Blob.service).to receive(:download).and_wrap_original do |metodo, chave, *resto, &bloco|
      raise 'a planilha original ou o arquivo conferido inteiro foi baixado' if [original, arquivo_conferido].include?(chave)

      metodo.call(chave, *resto, &bloco)
    end
    # Do arquivo conferido só o começo é lido, para os exemplos (Relacionamentos::Trazer::LinhasDaPlanilha).
    allow(ActiveStorage::Blob.service).to receive(:download_chunk).and_wrap_original do |metodo, chave, *resto|
      raise 'a planilha original foi baixada' if chave == original

      metodo.call(chave, *resto)
    end

    corpo = ler(importacao)
    expect(response).to have_http_status(:ok)
    expect(corpo['problemas'].first).to include('linha' => 4, 'estado' => 'guardado', 'corrigido' => '+5511987650004')
    expect(corpo['exemplos'].size).to eq(2)

    [-> { consertar(importacao, 5, valor: 'davi@exemplo.com.br') }, -> { deixar_de_fora(importacao, 7) }, -> { reabrir(importacao, 4) },
     -> { consertar(importacao, 8, ficar_com: 8) }].each do |pedir|
      pedir.call
      expect(response).to have_http_status(:ok)
    end
  end

  it 'na linha repetida, a pessoa escolhe com qual das duas fica' do
    importacao = ler_planilha(com_problemas)

    consertar(importacao, 8, ficar_com: 2)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['problema']).to include('linha' => 8, 'tipo' => 'duplicada', 'outraLinha' => 2, 'estado' => 'deixado')
    expect(importacao.reload.options['trazer']).to eq('deixadas' => [8])

    consertar(importacao, 8, ficar_com: 8)
    expect(response.parsed_body['problema']).to include('linha' => 8, 'estado' => 'guardado', 'ficar_com' => 8)
    expect(response.parsed_body['problema']).not_to have_key('corrigido')
    expect(importacao.reload.options['trazer']).to eq('deixadas' => [])
    expect(consertos(importacao).keys).to eq([8])
    expect(ContactImports::Trazer::Consertos.new(importacao).ler[8]).to include('campo' => 'ficar_com', 'outra' => 2)

    reabrir(importacao, 8)
    expect(response.parsed_body['problema']).to include('linha' => 8, 'estado' => 'aberto')
    expect(importacao.reload.options['trazer']).to eq('deixadas' => [])
    expect(importacao.consertos).not_to be_attached

    [nil, 3, 99, 'abc'].each do |escolhida|
      consertar(importacao, 8, ficar_com: escolhida)

      expect(response).to have_http_status(:unprocessable_entity), escolhida.inspect
      expect(response.parsed_body).to eq('error' => 'valor_invalido', 'motivo' => 'linha_desconhecida')
    end
  end

  it 'deixa de fora e volta atrás, sem corpo no pedido; voltar atrás esquece o que tinha sido guardado' do
    importacao = ler_planilha(com_problemas)

    deixar_de_fora(importacao, 7)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      'problema' => { 'linha' => 7, 'tipo' => 'sem_contato', 'nome' => 'Elisa Esteveira', 'valor' => '', 'estado' => 'deixado' }, 'entram' => 2
    )

    consertar(importacao, 4, valor: '11987650004')
    deixar_de_fora(importacao, 4)
    expect(response.parsed_body['problema']).to include('linha' => 4, 'estado' => 'deixado')
    expect(response.parsed_body['problema']).not_to have_key('corrigido')
    expect(estados(importacao)).to eq(4 => 'deixado', 5 => 'aberto', 6 => 'aberto', 7 => 'deixado', 8 => 'aberto')

    reabrir(importacao, 4)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['problema']).to eq('linha' => 4, 'tipo' => 'telefone', 'nome' => 'Carla Carvalhedo', 'valor' => '(11) 2345-678',
                                                   'estado' => 'aberto', 'motivo' => 'invalid_brazilian_mobile_number')
    expect(importacao.reload.options['trazer']).to eq('deixadas' => [7])
    expect(importacao.consertos).not_to be_attached
  end

  it 'recusa a linha que não é problema, e tudo enquanto a planilha é lida de novo ou depois de trazida' do
    importacao = ler_planilha(com_problemas)

    [2, 99, 'abc'].each do |linha|
      pedidos = [-> { consertar(importacao, linha, valor: '11987650004') }, -> { deixar_de_fora(importacao, linha) },
                 -> { reabrir(importacao, linha) }]
      pedidos.each do |pedir|
        pedir.call

        expect(response).to have_http_status(:unprocessable_entity), linha.inspect
        expect(response.parsed_body).to eq('error' => 'linha_desconhecida')
      end
    end

    %i[validating confirmed queued importing completed].each do |estado|
      importacao.update!(status: estado)
      [-> { consertar(importacao, 4, valor: '11987650004') }, -> { deixar_de_fora(importacao, 4) }, -> { reabrir(importacao, 4) }].each do |pedir|
        pedir.call

        expect(response).to have_http_status(:unprocessable_entity), estado.to_s
        expect(response.parsed_body).to eq('error' => 'leitura_nao_pronta')
      end
    end
    expect(importacao.reload.options['trazer']).to eq({})
  end

  it 'não conserta depois que o arquivo das linhas com problema foi apagado, mas ainda deixa de fora' do
    importacao = ler_planilha(com_problemas)
    importacao.linhas_com_problema.purge

    consertar(importacao, 4, valor: '11987650004')
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'planilha_apagada')

    deixar_de_fora(importacao, 4)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['problema']).to include('linha' => 4, 'estado' => 'deixado')
  end

  it 'ler a planilha de novo (trocar uma coluna) mantém o que foi consertado e o que foi deixado de fora' do
    importacao = ler_planilha(com_problemas)
    consertar(importacao, 4, valor: '11987650004')
    consertar(importacao, 6, valor: 'Fabio Ferreirinho')
    consertar(importacao, 8, ficar_com: 8)
    deixar_de_fora(importacao, 7)
    antes = consertos(importacao)

    trocar(importacao, 3, destino: 'empresa')
    expect(response.parsed_body).to eq('id' => importacao.id, 'situacao' => 'lendo')
    ler_de_novo

    expect(importacao.reload.options['trazer']['deixadas']).to eq([7])
    expect(consertos(importacao)).to eq(antes)
    expect(estados(importacao)).to eq(4 => 'guardado', 5 => 'aberto', 6 => 'guardado', 7 => 'deixado', 8 => 'guardado')
    expect(response.parsed_body['problemas'].to_h { |problema| [problema['linha'], problema['corrigido']] })
      .to include(4 => '+5511987650004', 6 => 'Fabio Ferreirinho')
    expect(conferido(importacao).pluck(:row_number, :phone_number)).to eq([[2, '+5511987650001'], [3, '+5511987650002']])
  end

  it 'a leitura que falha não apaga o que foi consertado: a próxima que dá certo mantém' do
    importacao = ler_planilha(com_problemas)
    consertar(importacao, 4, valor: '11987650004')
    deixar_de_fora(importacao, 7)

    allow(CampaignImports::Parser).to receive(:new).and_raise(IOError)
    perform_enqueued_jobs { CampaignImports::ValidateJob.perform_later(importacao) }
    expect(ler(importacao)).to eq('id' => importacao.id, 'situacao' => 'falhou', 'erro' => 'leitura')
    expect(importacao.reload.normalized_csv).not_to be_attached
    expect(importacao.consertos).to be_attached

    allow(CampaignImports::Parser).to receive(:new).and_call_original
    perform_enqueued_jobs { CampaignImports::ValidateJob.perform_later(importacao) }
    expect(estados(importacao)).to eq(4 => 'guardado', 5 => 'aberto', 6 => 'aberto', 7 => 'deixado', 8 => 'aberto')
    expect(response.parsed_body['problemas'].first).to include('linha' => 4, 'corrigido' => '+5511987650004')
  end

  # Decisão do dono: "deixar de fora" responde a um problema. Se a leitura nova acabou com o problema, a linha é
  # pessoa boa, entra, e o resumo conta com ela.
  it 'a linha deixada de fora que a leitura nova torna válida entra na lista' do
    # Colunas: 0 Nome, 1 Celular, 2 Fone 2. O celular da Carla está errado; o outro telefone dela vale.
    importacao = ler_planilha("Nome;Celular;Fone 2\nAna Albuquerino;11987650001;11987650009\nCarla Carvalhedo;(11) 2345-678;11987650003\n")
    deixar_de_fora(importacao, 3)
    expect(estados(importacao)).to eq(3 => 'deixado')

    trocar(importacao, 2, destino: 'telefone')
    ler_de_novo
    corpo = ler(importacao)

    expect(corpo['resumo']).to include('total' => 2, 'novas' => 2, 'comProblema' => 0)
    expect(corpo['problemas']).to eq([])
    trazer(importacao)
    gravar_a_lista
    expect(account.contacts.pluck(:name, :phone_number))
      .to contain_exactly(['Ana Albuquerino', '+5511987650009'], ['Carla Carvalhedo', '+5511987650003'])
  end

  it 'ler de novo esquece o conserto da linha que deixou de ter problema e a marca da linha que sumiu' do
    importacao = ler_planilha(com_problemas)
    consertar(importacao, 5, valor: 'davi@exemplo.com.br')
    deixar_de_fora(importacao, 4)
    importacao.original_file.attach(io: StringIO.new("Nome;Celular;E-mail;Plano\nAna;11987650001;;\nBia;123;;\n"), filename: 'Clientes 2025.csv',
                                    content_type: 'text/csv')

    perform_enqueued_jobs { CampaignImports::ValidateJob.perform_later(importacao) }

    expect(importacao.reload.options['trazer']['deixadas']).to eq([])
    expect(importacao.consertos).not_to be_attached
    expect(estados(importacao)).to eq(3 => 'aberto')
  end

  # C2: quantas pessoas entram se a pessoa clicar em "Trazer" agora, a mesma conta que o "Trazer" faz.
  it 'diz quantas pessoas entram agora, na leitura e em cada resposta de quem mexe numa linha' do
    importacao = ler_planilha(com_problemas)
    expect(ler(importacao)['resumo']).to include('entram' => 2)

    consertar(importacao, 4, valor: '11987650004')
    expect(response.parsed_body['entram']).to eq(3)
    # Ficar com a repetida põe a linha 8 e tira a 2, que estava aprovada.
    consertar(importacao, 8, ficar_com: 8)
    expect(response.parsed_body['entram']).to eq(3)
    deixar_de_fora(importacao, 4)
    expect(response.parsed_body['entram']).to eq(2)
    reabrir(importacao, 8)
    expect(response.parsed_body['entram']).to eq(2)
    consertar(importacao, 5, valor: 'davi@exemplo.com.br')
    expect(response.parsed_body['entram']).to eq(3)
    expect(ler(importacao)['resumo']).to include('entram' => 3, 'novas' => 2, 'comProblema' => 5)

    trazer(importacao)
    gravar_a_lista
    expect(importacao.reload.valid_rows).to eq(3)
    expect(account.contacts.count).to eq(3)
  end

  # M2: a linha consertada que depois perde o lugar para uma repetida não volta a entrar.
  it 'a linha consertada que a pessoa trocou por uma repetida dela não entra' do
    # Linha 2: sem nome. Linha 4: a mesma pessoa (mesmo telefone), com outro e-mail.
    linhas = ['Nome;Celular;E-mail', ';11987650001;ana@exemplo.com.br', 'Bruno Brandolim;11987650002;', 'Ana Outra;11987650001;outra@exemplo.com.br']
    importacao = ler_planilha("#{linhas.join("\n")}\n")
    expect(ler(importacao)['problemas'].pluck('linha', 'tipo')).to eq([[2, 'nome'], [4, 'duplicada']])

    consertar(importacao, 2, valor: 'Ana Albuquerino')
    expect(response.parsed_body['entram']).to eq(2)
    consertar(importacao, 4, ficar_com: 4)
    expect(response.parsed_body['entram']).to eq(2)

    trazer(importacao)
    gravar_a_lista
    expect(importacao.reload).to have_attributes(status: 'completed', valid_rows: 2, invalid_rows: 1)
    expect(account.contacts.pluck(:name, :email)).to contain_exactly(['Bruno Brandolim', nil], ['Ana Outra', 'outra@exemplo.com.br'])
  end

  # M3: num grupo de linhas da mesma pessoa entra uma só.
  it 'num grupo de linhas repetidas, ficar com uma deixa as outras do grupo de fora, inclusive a escolhida antes' do
    linhas = ['Nome;Celular;E-mail', 'Ana Albuquerino;11987650001;', 'Bruno Brandolim;11987650002;', 'Ana Outra;11987650001;',
              'Ana Terceira;11987650001;']
    importacao = ler_planilha("#{linhas.join("\n")}\n")
    expect(ler(importacao)['problemas'].pluck('linha', 'tipo', 'outraLinha')).to eq([[4, 'duplicada', 2], [5, 'duplicada', 2]])

    consertar(importacao, 4, ficar_com: 4)
    expect(response.parsed_body).to include('entram' => 2)
    expect(response.parsed_body['problema']).to include('linha' => 4, 'estado' => 'guardado', 'ficar_com' => 4)
    expect(estados(importacao)).to eq(4 => 'guardado', 5 => 'deixado')

    consertar(importacao, 5, ficar_com: 5)
    expect(response.parsed_body).to include('entram' => 2)
    expect(estados(importacao)).to eq(4 => 'deixado', 5 => 'guardado')
    expect(consertos(importacao).keys).to eq([5])

    trazer(importacao)
    gravar_a_lista
    expect(account.contacts.pluck(:name, :phone_number)).to contain_exactly(['Bruno Brandolim', '+5511987650002'], ['Ana Terceira', '+5511987650001'])
  end

  # M4: a linha que juntou outra da mesma pessoa leva, no conserto, o que veio da outra.
  it 'a linha sem nome que juntou outra linha da pessoa entra com o e-mail e a empresa que vieram da outra' do
    linhas = ['Nome;Celular;E-mail;Empresa', ';11987650001;;', ';11987650001;ana@exemplo.com.br;Padaria Bom Dia', 'Bruno Brandolim;11987650002;;']
    importacao = ler_planilha("#{linhas.join("\n")}\n")
    expect(ler(importacao)['problemas'].pluck('linha', 'tipo')).to eq([[2, 'nome']])

    consertar(importacao, 2, valor: 'Ana Albuquerino')

    expect(response.parsed_body['problema']).to include('estado' => 'guardado', 'corrigido' => 'Ana Albuquerino')
    expect(ContactImports::Trazer::Consertos.new(importacao.reload).ler[2]['conferida']).to include(
      'name' => 'Ana Albuquerino', 'phone_number' => '+5511987650001', 'email' => 'ana@exemplo.com.br', 'company_name' => 'Padaria Bom Dia'
    )
  end

  # M6: entre o commit da leitura e o envio dos anexos ao armazenamento, o anexo existe no banco e o arquivo ainda não.
  it 'com o anexo no banco e o arquivo ainda fora do armazenamento, a leitura responde "lendo" e a escrita é recusada' do
    importacao = ler_planilha(com_problemas)
    anexo = importacao.linhas_com_problema.blob
    anexo.service.delete(anexo.key)

    expect(ler(importacao)).to eq('id' => importacao.id, 'situacao' => 'lendo')
    expect(response).to have_http_status(:ok)
    consertar(importacao, 4, valor: '11987650004')
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'leitura_nao_pronta')
    expect(importacao.reload.consertos).not_to be_attached
  end

  # F4: o envio ao armazenamento é depois do commit. Se ele falhou, o arquivo não vem mais: a tela não espera para sempre.
  it 'o arquivo que não chegou ao armazenamento dois minutos depois não vem mais: a leitura responde "falhou"' do
    importacao = ler_planilha(com_problemas)
    anexo = importacao.linhas_com_problema.blob
    anexo.service.delete(anexo.key)

    travel_to(119.seconds.from_now) { expect(ler(importacao)).to eq('id' => importacao.id, 'situacao' => 'lendo') }
    travel_to(121.seconds.from_now) do
      expect(ler(importacao)).to eq('id' => importacao.id, 'situacao' => 'falhou', 'erro' => 'leitura')
      expect(response).to have_http_status(:ok)
      consertar(importacao, 4, valor: '11987650004')
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'leitura_nao_pronta')
    end
    expect(importacao.reload).to be_ready_to_confirm
  end

  # M8: um conserto lê cada anexo uma vez só.
  it 'um conserto baixa o arquivo das linhas com problema e o dos consertos uma vez cada' do
    importacao = ler_planilha(com_problemas)
    consertar(importacao, 4, valor: '11987650004')
    baixados = Hash.new(0)
    allow(ActiveStorage::Blob.service).to receive(:download).and_wrap_original do |metodo, chave, *resto, &bloco|
      baixados[chave] += 1
      metodo.call(chave, *resto, &bloco)
    end

    consertar(importacao, 5, valor: 'davi@exemplo.com.br')

    expect(response).to have_http_status(:ok)
    expect(baixados.size).to eq(2)
    expect(baixados.values).to all(eq(1))
  end

  # B5: o conserto vale para a coluna em que foi feito.
  it 'ler de novo com outra coluna no lugar esquece o conserto feito na coluna antiga' do
    # Colunas: 0 Nome, 1 Celular, 2 Fone 2. A Carla tem os dois telefones errados.
    importacao = ler_planilha("Nome;Celular;Fone 2\nAna Albuquerino;11987650001;11987650009\nCarla Carvalhedo;(11) 2345-678;(11) 2345-679\n")
    consertar(importacao, 3, valor: '11987650003')
    expect(estados(importacao)).to eq(3 => 'guardado')

    trocar(importacao, 2, destino: 'telefone')
    ler_de_novo

    aberto = include('linha' => 3, 'tipo' => 'telefone', 'valor' => '(11) 2345-679', 'estado' => 'aberto')
    expect(ler(importacao)['problemas']).to contain_exactly(aberto)
    expect(importacao.reload.consertos).not_to be_attached
  end

  # B1: a leitura que quebra depois de conferir as linhas não regrava os consertos só com os que ela ia manter.
  it 'a leitura que quebra no fim não apaga o conserto da linha que ela ia esquecer' do
    importacao = ler_planilha(com_problemas)
    consertar(importacao, 4, valor: '11987650004')
    consertar(importacao, 5, valor: 'davi@exemplo.com.br')
    # Na planilha nova a linha 5 deixa de ter problema: a leitura que desse certo esqueceria o conserto dela.
    importacao.original_file.attach(io: StringIO.new(com_problemas.sub('davi.dornelino.exemplo.com.br', 'davi@exemplo.com.br')),
                                    filename: 'Clientes 2025.csv', content_type: 'text/csv')
    allow_any_instance_of(ContactImports::Trazer::Validador).to receive(:attach_normalized_csv).and_raise(IOError) # rubocop:disable RSpec/AnyInstance

    perform_enqueued_jobs { CampaignImports::ValidateJob.perform_later(importacao) }

    expect(ler(importacao)).to include('situacao' => 'falhou')
    expect(consertos(importacao).keys).to eq([4, 5])
  end
end

require 'rails_helper'

# #2896 — "Trazer minha lista" (Fatia 1): enviar a planilha, ler o que o sistema achou, trocar o destino de uma coluna,
# acompanhar a lista entrando e ver as listas já trazidas. As regras de cada peça estão em
# spec/services/relacionamentos/trazer e em spec/services/contact_imports/validator_trazer_spec.rb.
RSpec.describe 'Trazer minha lista (Relacionamentos)', :aggregate_failures, type: :request do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/relacionamentos/trazer" }
  let(:ligadas) { { 'CAMPAIGN_JOURNEY_ENABLED' => 'true', 'CAMPAIGN_IMPORT_ENABLED' => 'true' } }
  let(:variaveis) { ligadas }
  let(:planilha) do
    <<~CSV
      Nome;Celular;E-mail;Empresa;Situação
      Ana Albuquerino;11987650001;ana.albuquerino@exemplo.com.br;Padaria Bom Dia;ativa
      Bruno Brandolim;11987650002;;;
      Carla Carvalhedo;(11) 2345-678;;;
      Davi Dornelino;;davi.dornelino.exemplo.com.br;;
      Elisa Esteveira;;;;
      Ana Repetida;11987650001;;;
    CSV
  end

  around { |example| with_modified_env(variaveis) { example.run } }

  before { account.enable_features!('relacionamentos_novo') }

  def cabecalhos(quem)
    quem.create_new_auth_token
  end

  def arquivo(texto, nome: 'Clientes 2025.csv')
    temporario = Tempfile.new(['lista', File.extname(nome)])
    temporario.write(texto)
    temporario.rewind
    Rack::Test::UploadedFile.new(temporario.path, 'text/csv', original_filename: nome)
  end

  def enviar(texto = planilha, quem: admin, **dados)
    post "#{base}/leituras", params: { arquivo: arquivo(texto, **dados) }, headers: cabecalhos(quem)
  end

  # Envia e deixa a leitura terminar, como o job faz em segundo plano.
  def ler_planilha(texto = planilha)
    perform_enqueued_jobs(only: CampaignImports::ValidateJob) { enviar(texto) }
    account.campaign_imports.order(:id).last
  end

  def ler(importacao, quem: admin, **params)
    get "#{base}/leituras/#{importacao.id}", params: params, headers: cabecalhos(quem)
  end

  def trocar(importacao, indice, destino, quem: admin)
    patch "#{base}/leituras/#{importacao.id}/colunas/#{indice}", params: { destino: destino }, headers: cabecalhos(quem), as: :json
  end

  def listas(quem: admin)
    get "#{base}/listas", headers: cabecalhos(quem)
  end

  def andamento(importacao, quem: admin)
    get "#{base}/listas/#{importacao.id}/andamento", headers: cabecalhos(quem)
  end

  def agente(permissoes: nil)
    pessoa = create(:user, account: account, role: :agent)
    pessoa.account_users.first.update!(custom_role: create(:custom_role, account: account, permissions: permissoes)) if permissoes
    pessoa
  end

  # Uma lista já na conta, sem passar pela leitura: `linhas` é { situação da linha => quantas }.
  def lista(situacao: :completed, conta: account, linhas: {}, opcoes: {}, **dados)
    importacao = conta.campaign_imports.create!(
      user: dados[:user] || create(:user, account: conta, role: :administrator), status: situacao, mode: 'single_label', batch_count: 1,
      options: { 'flow' => CampaignImport::CONTACTS_FLOW }.merge(opcoes), source_filename: 'Clientes de setembro.xlsx',
      valid_rows: linhas.values.sum, **dados
    )
    estados = linhas.flat_map { |estado, quantas| [estado] * quantas }
    estados.each_with_index { |estado, vez| importacao.campaign_import_rows.create!(row_number: vez + 2, status: estado) }
    importacao
  end

  def consultas_feitas(&)
    feitas = 0
    contar = ->(*, dados) { feitas += 1 unless dados[:cached] || %w[SCHEMA TRANSACTION].include?(dados[:name]) }
    ActiveSupport::Notifications.subscribed(contar, 'sql.active_record', &)
    feitas
  end

  # Cada rota desta fatia, para as conferências de quem pode entrar.
  def cada_rota(quem)
    importacao = lista
    {
      'POST leituras' => -> { enviar(quem: quem) },
      'GET leituras/:id' => -> { ler(importacao, quem: quem) },
      'PATCH leituras/:id/colunas/:indice' => -> { trocar(importacao, 0, 'nome', quem: quem) },
      'GET listas' => -> { listas(quem: quem) },
      'GET listas/:id/andamento' => -> { andamento(importacao, quem: quem) }
    }
  end

  describe 'quem pode entrar' do
    it 'responde 401 sem login' do
      importacao = lista

      post "#{base}/leituras", params: { arquivo: arquivo(planilha) }
      expect(response).to have_http_status(:unauthorized)
      get "#{base}/leituras/#{importacao.id}"
      expect(response).to have_http_status(:unauthorized)
      patch "#{base}/leituras/#{importacao.id}/colunas/0", params: { destino: 'nome' }, as: :json
      expect(response).to have_http_status(:unauthorized)
      get "#{base}/listas"
      expect(response).to have_http_status(:unauthorized)
      get "#{base}/listas/#{importacao.id}/andamento"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'responde 404 em todas as rotas com a chave da conta desligada' do
      rotas = cada_rota(admin)
      account.disable_features!('relacionamentos_novo')

      rotas.each do |nome, pedir|
        pedir.call

        expect(response).to have_http_status(:not_found), nome
      end
      expect(account.campaign_imports.count).to eq(1)
    end

    describe 'com a importação por planilha desligada na instalação' do
      let(:variaveis) { ligadas.merge('CAMPAIGN_IMPORT_ENABLED' => 'false') }

      it 'responde 404 em todas as rotas' do
        cada_rota(admin).each do |nome, pedir|
          pedir.call

          expect(response).to have_http_status(:not_found), nome
        end
        expect(account.campaign_imports.count).to eq(1)
      end
    end

    it 'recusa em todas as rotas, leituras inclusive, o agente sem a permissão de importar contatos' do
      [agente, agente(permissoes: ['contact_view']), agente(permissoes: ['campaign_manage'])].each do |pessoa|
        cada_rota(pessoa).each do |nome, pedir|
          pedir.call

          expect(response).to have_http_status(:unauthorized), nome
        end
      end
      expect(account.campaign_imports.where("options -> 'trazer' IS NOT NULL").count).to eq(0)
    end

    it 'atende a função com contact_manage' do
      pessoa = agente(permissoes: ['contact_manage'])

      enviar(quem: pessoa)
      expect(response).to have_http_status(:created)

      listas(quem: pessoa)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST leituras' do
    it 'guarda a planilha como importação de contatos com a marca "trazer" e põe a leitura na fila' do
      expect { enviar }.to have_enqueued_job(CampaignImports::ValidateJob).once

      importacao = account.campaign_imports.sole
      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to eq('id' => importacao.id, 'situacao' => 'lendo')
      expect(importacao).to have_attributes(status: 'uploaded', user_id: admin.id, source_filename: 'Clientes 2025.csv', source_format: 'csv')
      expect(importacao).to be_contact_import
      expect(importacao.options).to include('flow' => 'contacts', 'trazer' => {})
      expect(importacao.original_file).to be_attached
    end

    it 'recusa o que não é planilha que o sistema lê, .xls inclusive' do
      ['foto.png', 'antiga.xls', 'sem_extensao'].each do |nome|
        enviar(nome: nome)

        expect(response).to have_http_status(:unprocessable_entity), nome
        expect(response.parsed_body).to eq('error' => 'tipo')
      end
      expect(account.campaign_imports.count).to eq(0)
    end

    it 'recusa o pedido sem arquivo' do
      post "#{base}/leituras", params: { arquivo: 'Clientes 2025.csv' }, headers: cabecalhos(admin)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'arquivo_obrigatorio')
      expect(account.campaign_imports.count).to eq(0)
    end

    it 'recusa o arquivo maior que o limite da instalação' do
      with_modified_env('CAMPAIGN_IMPORT_MAX_FILE_SIZE_MB' => '0') { enviar }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'arquivo_grande')
      expect(account.campaign_imports.count).to eq(0)
    end
  end

  describe 'GET leituras/:id' do
    it 'diz "lendo" sem abrir o arquivo enquanto a leitura não termina' do
      enviar
      importacao = account.campaign_imports.sole
      allow(Relacionamentos::Trazer::LinhasDaPlanilha).to receive(:new).and_call_original

      ler(importacao)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('id' => importacao.id, 'situacao' => 'lendo')
      expect(Relacionamentos::Trazer::LinhasDaPlanilha).not_to have_received(:new)
    end

    it 'devolve a leitura pronta no formato da tela, com os valores inteiros de cada linha com problema' do
      create(:contact, account: account, name: 'Bruno', phone_number: '+5511987650002')
      importacao = ler_planilha

      ler(importacao)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        'id' => importacao.id, 'situacao' => 'pronta', 'arquivo' => 'Clientes 2025.csv', 'valores' => 'inteiros',
        'colunas' => [
          { 'indice' => 0, 'nome' => 'Nome', 'destino' => 'nome', 'duvidosa' => true },
          { 'indice' => 1, 'nome' => 'Celular', 'destino' => 'telefone', 'duvidosa' => true },
          { 'indice' => 2, 'nome' => 'E-mail', 'destino' => 'email', 'duvidosa' => true },
          { 'indice' => 3, 'nome' => 'Empresa', 'destino' => 'empresa', 'duvidosa' => true },
          { 'indice' => 4, 'nome' => 'Situação', 'destino' => 'informacao', 'campo' => { 'nome' => 'Situação', 'para_que_serve' => '' } }
        ],
        'perguntas' => [], 'respostas' => {},
        'resumo' => { 'total' => 6, 'novas' => 1, 'completadas' => 1, 'comProblema' => 4 },
        'exemplos' => [
          { 'nome' => 'Ana Albuquerino', 'telefone' => '+5511987650001', 'email' => 'ana.albuquerino@exemplo.com.br',
            'empresa' => 'Padaria Bom Dia', 'cliente' => false },
          { 'nome' => 'Bruno Brandolim', 'telefone' => '+5511987650002', 'email' => '', 'empresa' => '', 'cliente' => false }
        ],
        'problemas' => [
          { 'linha' => 4, 'tipo' => 'telefone', 'nome' => 'Carla Carvalhedo', 'valor' => '(11) 2345-678', 'estado' => 'aberto' },
          { 'linha' => 5, 'tipo' => 'email', 'nome' => 'Davi Dornelino', 'valor' => 'davi.dornelino.exemplo.com.br', 'estado' => 'aberto' },
          { 'linha' => 6, 'tipo' => 'sem_contato', 'nome' => 'Elisa Esteveira', 'valor' => '', 'estado' => 'aberto' },
          { 'linha' => 7, 'tipo' => 'duplicada', 'nome' => 'Ana Repetida', 'valor' => '11987650001', 'estado' => 'aberto', 'outraLinha' => 2,
            'duplicadas' => [{ 'linha' => 2, 'telefone' => '11987650001', 'email' => 'ana.albuquerino@exemplo.com.br' },
                             { 'linha' => 7, 'telefone' => '11987650001', 'email' => '' }] }
        ],
        'problemas_total' => 4, 'pagina' => 1, 'por_pagina' => 200
      )
    end

    # O nome é a exceção declarada: o validador de planilhas já o guarda inteiro em cada linha (raw_name e normalized_name).
    it 'não guarda telefone nem e-mail inteiro de linha nenhuma, aprovada ou com problema' do
      importacao = ler_planilha
      linhas = importacao.campaign_import_rows.map { |linha| linha.attributes.except('raw_name', 'normalized_name') }

      expect(linhas.size).to eq(6)
      guardado = [importacao.options, importacao.validation_summary, importacao.schema_resolution, linhas].to_json
      expect(guardado).not_to include('11987650001', '11987650002', 'ana.albuquerino', '2345-678', '112345678', 'davi.dornelino')
    end

    it 'não entrega telefone nem e-mail inteiro quando os dois arquivos já foram apagados; o nome continua' do
      importacao = ler_planilha
      importacao.original_file.purge
      importacao.normalized_csv.purge

      ler(importacao)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('situacao' => 'pronta', 'valores' => 'mascarados', 'exemplos' => [])
      expect(response.parsed_body['problemas'].pluck('nome')).to eq(['Carla Carvalhedo', 'Davi Dornelino', 'Elisa Esteveira', 'Ana Repetida'])
      expect(response.body).not_to include('11987650001', '11987650002', 'ana.albuquerino', '2345-678', '112345678', 'davi.dornelino')
    end

    it 'leva à primeira ou à última página o número de página que não existe, sem quebrar' do
      importacao = ler_planilha

      ['0', '-3', 'abc', '2', '99999999999999999999999999'].each do |pagina|
        ler(importacao, pagina: pagina)

        expect(response).to have_http_status(:ok), pagina
        expect(response.parsed_body).to include('pagina' => 1, 'problemas_total' => 4), pagina
        expect(response.parsed_body['problemas'].size).to eq(4), pagina
      end
    end

    it 'devolve só as máscaras quando a planilha original já foi apagada' do
      importacao = ler_planilha
      importacao.original_file.purge

      ler(importacao)

      corpo = response.parsed_body
      expect(response).to have_http_status(:ok)
      expect(corpo).to include('situacao' => 'pronta', 'valores' => 'mascarados', 'problemas_total' => 4)
      expect(corpo['problemas'].map { |problema| problema.slice('linha', 'tipo', 'valor') }).to eq(
        [
          { 'linha' => 4, 'tipo' => 'telefone', 'valor' => importacao.campaign_import_rows.find_by!(row_number: 4).raw_phone_masked },
          { 'linha' => 5, 'tipo' => 'email', 'valor' => importacao.campaign_import_rows.find_by!(row_number: 5).email_masked },
          { 'linha' => 6, 'tipo' => 'sem_contato', 'valor' => '' },
          { 'linha' => 7, 'tipo' => 'duplicada', 'valor' => importacao.campaign_import_rows.find_by!(row_number: 7).raw_phone_masked }
        ]
      )
      expect(corpo['problemas'].last).to include('outraLinha' => nil, 'duplicadas' => [])
      expect(corpo['problemas'].to_json).not_to include('2345-678', '112345678', 'davi.dornelino.exemplo.com.br', '11987650001')
    end

    it 'diz que a planilha está vazia' do
      importacao = ler_planilha("Nome;Celular\n")

      ler(importacao)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('id' => importacao.id, 'situacao' => 'falhou', 'erro' => 'vazia')
    end

    it 'diz que não achou telefone nem e-mail quando a planilha não tem coluna de contato' do
      importacao = ler_planilha("Nome;Cidade\nAna Albuquerino;Campinas\nBruno Brandolim;Santos\n")

      ler(importacao)

      expect(response.parsed_body).to eq('id' => importacao.id, 'situacao' => 'falhou', 'erro' => 'sem_contato')
    end

    it 'diz que não achou contato quando nenhuma linha tem telefone ou e-mail que valha' do
      importacao = ler_planilha("Nome;Celular\nAna Albuquerino;123\nBruno Brandolim;456\n")

      ler(importacao)

      expect(response.parsed_body).to eq('id' => importacao.id, 'situacao' => 'falhou', 'erro' => 'sem_contato')
    end

    it 'responde 404 para a leitura de outra conta, da automação, de Públicos, da tela antiga e para a lista já trazida' do
      outra_conta = create(:account)
      outra_conta.enable_features!('relacionamentos_novo')
      de_fora = [
        lista(situacao: :ready_to_confirm, conta: outra_conta, opcoes: { 'trazer' => {} }),
        lista(situacao: :ready_to_confirm, opcoes: { 'trazer' => {}, 'origem' => CampaignImport::AUTOMATION_ORIGIN }),
        lista(situacao: :ready_to_confirm, opcoes: { 'trazer' => {}, 'flow' => CampaignImport::AUDIENCE_FLOW }),
        lista(situacao: :ready_to_confirm),
        lista(situacao: :completed, opcoes: { 'trazer' => {} })
      ]

      de_fora.each do |importacao|
        ler(importacao)
        expect(response).to have_http_status(:not_found), importacao.options.to_json

        trocar(importacao, 0, 'nome')
        expect(response).to have_http_status(:not_found), importacao.options.to_json
      end
    end
  end

  describe 'PATCH leituras/:id/colunas/:indice' do
    let(:dois_telefones) do
      <<~CSV
        Nome;Celular;Fone 2;Cidade
        Ana Albuquerino;11987650001;11987650091;Campinas
        Bruno Brandolim;;11987650092;Santos
      CSV
    end

    it 'troca a coluna de um dos quatro alvos e lê a planilha de novo' do
      importacao = ler_planilha(dois_telefones)
      expect(importacao.reload).to have_attributes(status: 'ready_to_confirm', valid_rows: 1, invalid_rows: 1)

      expect { trocar(importacao, 2, 'telefone') }.to have_enqueued_job(CampaignImports::ValidateJob).with(importacao)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('id' => importacao.id, 'situacao' => 'lendo')
      expect(importacao.reload).to be_validating
      expect(importacao.schema_resolution['manual_mapping']).to eq('name' => 0, 'phone' => 2, 'email' => nil, 'company' => nil)

      perform_enqueued_jobs(only: CampaignImports::ValidateJob)
      ler(importacao)

      expect(importacao.reload).to have_attributes(status: 'ready_to_confirm', valid_rows: 2, invalid_rows: 0)
      expect(response.parsed_body['colunas']).to eq(
        [
          { 'indice' => 0, 'nome' => 'Nome', 'destino' => 'nome' },
          { 'indice' => 1, 'nome' => 'Celular', 'destino' => 'informacao', 'campo' => { 'nome' => 'Celular', 'para_que_serve' => '' } },
          { 'indice' => 2, 'nome' => 'Fone 2', 'destino' => 'telefone' },
          { 'indice' => 3, 'nome' => 'Cidade', 'destino' => 'informacao', 'campo' => { 'nome' => 'Cidade', 'para_que_serve' => '' } }
        ]
      )
    end

    it 'tira a coluna do alvo quando ela deixa de ser guardada, lê de novo e não guarda o valor dela' do
      importacao = ler_planilha

      expect { trocar(importacao, 3, 'nao_guardar') }.to have_enqueued_job(CampaignImports::ValidateJob).with(importacao)

      expect(response.parsed_body).to eq('id' => importacao.id, 'situacao' => 'lendo')
      importacao.reload
      expect(importacao.schema_resolution['manual_mapping']).to eq('name' => 0, 'phone' => 1, 'email' => 2, 'company' => nil)
      expect(importacao.options.dig('trazer', 'destinos')).to eq('3' => 'nao_guardar')

      perform_enqueued_jobs(only: CampaignImports::ValidateJob)

      expect(importacao.reload).to be_ready_to_confirm
      expect(importacao.extra_columns).to eq(%w[Empresa Situação])
      expect(importacao.campaign_import_rows.order(:row_number).first.extra_values).to eq('Situação' => 'ativa')
      expect(importacao.campaign_import_rows.map(&:attributes).to_json).not_to include('Padaria Bom Dia')
      expect(importacao.validation_summary['contact_attributes'].pluck('column')).to eq(['Situação'])
    end

    it 'não lê de novo quando a coluna já está no destino pedido' do
      importacao = ler_planilha

      expect { trocar(importacao, 1, 'telefone') }.not_to have_enqueued_job(CampaignImports::ValidateJob)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('id' => importacao.id, 'situacao' => 'pronta')
      expect(importacao.reload).to be_ready_to_confirm
    end

    it 'na coluna extra que não é para guardar, apaga na hora o valor de todas as linhas, sem ler de novo' do
      importacao = ler_planilha
      expect(importacao.campaign_import_rows.order(:row_number).first.extra_values).to eq('Situação' => 'ativa')

      expect { trocar(importacao, 4, 'nao_guardar') }.not_to have_enqueued_job(CampaignImports::ValidateJob)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.keys).to contain_exactly('id', 'situacao', 'colunas')
      expect(response.parsed_body).to include('id' => importacao.id, 'situacao' => 'pronta')
      expect(response.parsed_body['colunas'].last).to eq('indice' => 4, 'nome' => 'Situação', 'destino' => 'nao_guardar')
      expect(importacao.reload).to be_ready_to_confirm
      expect(importacao.options['trazer']).to eq('destinos' => { '4' => 'nao_guardar' })
      expect(importacao.campaign_import_rows.pluck(:extra_values)).to all(eq({}))
      expect(importacao.campaign_import_rows.map(&:attributes).to_json).not_to include('ativa')
    end

    it 'lê a planilha de novo quando a coluna volta a ser informação, para o valor voltar do arquivo' do
      importacao = ler_planilha
      trocar(importacao, 4, 'nao_guardar')

      expect { trocar(importacao, 4, 'informacao') }.to have_enqueued_job(CampaignImports::ValidateJob).with(importacao)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('id' => importacao.id, 'situacao' => 'lendo')
      expect(importacao.reload).to be_validating
      expect(importacao.options['trazer']).to eq('destinos' => {})

      perform_enqueued_jobs(only: CampaignImports::ValidateJob)
      ler(importacao)

      expect(importacao.reload).to be_ready_to_confirm
      expect(importacao.campaign_import_rows.order(:row_number).first.extra_values).to eq('Situação' => 'ativa')
      expect(response.parsed_body['colunas'].last)
        .to eq('indice' => 4, 'nome' => 'Situação', 'destino' => 'informacao', 'campo' => { 'nome' => 'Situação', 'para_que_serve' => '' })
    end

    it 'recusa a coluna que a planilha não tem e o destino que esta fatia não conhece' do
      importacao = ler_planilha

      %w[5 -1 abc].each do |indice|
        trocar(importacao, indice, 'telefone')

        expect(response).to have_http_status(:unprocessable_entity), indice
        expect(response.parsed_body).to eq('error' => 'coluna_desconhecida')
      end

      ['cidade', 'qualquer', '', nil].each do |destino|
        trocar(importacao, 4, destino)

        expect(response).to have_http_status(:unprocessable_entity), destino.inspect
        expect(response.parsed_body).to eq('error' => 'destino_desconhecido')
      end
      expect(importacao.reload).to be_ready_to_confirm
      expect(importacao.options['trazer']).to eq({})
    end

    it 'recusa tirar a última coluna de contato' do
      importacao = ler_planilha("Nome;Celular;Cidade\nAna Albuquerino;11987650001;Campinas\n")

      %w[informacao nao_guardar nome].each do |destino|
        expect { trocar(importacao, 1, destino) }.not_to have_enqueued_job(CampaignImports::ValidateJob)

        expect(response).to have_http_status(:unprocessable_entity), destino
        expect(response.parsed_body).to eq('error' => 'sem_contato')
      end
      expect(importacao.reload).to be_ready_to_confirm
      expect(importacao.schema_resolution).not_to have_key('manual_mapping')
      expect(importacao.options['trazer']).to eq({})
    end

    it 'recusa a troca enquanto a leitura não terminou' do
      enviar
      importacao = account.campaign_imports.sole

      expect { trocar(importacao, 1, 'telefone') }.not_to have_enqueued_job(CampaignImports::ValidateJob)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'leitura_nao_pronta')
    end
  end

  describe 'GET listas' do
    it 'devolve as listas trazidas por arquivo, a mais nova primeiro, no formato da tela' do
      travel_to(Time.zone.parse('2026-11-08 14:03:00')) do
        marina = create(:user, account: account, role: :administrator, name: 'Marina Pavanelli')
        antiga = lista(user: marina, linhas: { imported: 3 }, confirmed_at: 3.days.ago, created_at: 4.days.ago)
        entrando = lista(situacao: :importing, user: marina, linhas: { imported: 1, valid: 3 }, confirmed_at: 1.minute.ago,
                         created_at: 1.hour.ago, import_started_at: 1.minute.ago)

        listas

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq(
          [
            { 'id' => entrando.id, 'arquivo' => 'Clientes de setembro.xlsx', 'quando' => '2026-11-08T14:02:00Z', 'quem' => 'Marina Pavanelli',
              'total' => 4, 'situacao' => 'trazendo', 'porcentagem' => 25, 'pode_tentar' => false },
            { 'id' => antiga.id, 'arquivo' => 'Clientes de setembro.xlsx', 'quando' => '2026-11-05T14:03:00Z', 'quem' => 'Marina Pavanelli',
              'total' => 3, 'situacao' => 'pronto', 'porcentagem' => 100, 'pode_tentar' => false }
          ]
        )
      end
    end

    it 'deixa de fora as da automação, os Públicos, os rascunhos e as de outra conta' do
      trazida = lista
      lista(opcoes: { 'origem' => CampaignImport::AUTOMATION_ORIGIN })
      lista(opcoes: { 'flow' => CampaignImport::AUDIENCE_FLOW })
      lista(conta: create(:account))
      %i[uploaded validating validation_failed ready_to_confirm needs_column_choice cancelled expired].each { |rascunho| lista(situacao: rascunho) }
      lista(situacao: :failed)

      listas

      expect(response.parsed_body.pluck('id')).to eq([trazida.id])
    end

    it 'devolve só as mais recentes quando a conta tem mais listas que o teto' do
      stub_const('Relacionamentos::Trazer::Historico::TETO', 2)
      lista(created_at: 3.days.ago)
      recentes = [lista(created_at: 1.day.ago), lista(created_at: 2.days.ago)]

      listas

      expect(response.parsed_body.pluck('id')).to eq(recentes.map(&:id))
    end

    it 'diz a situação de cada lista e quando dá para tentar de novo' do
      desfeita = lista(undo_status: :completed)
      desfazendo = lista(undo_status: :processing)
      parou = lista(situacao: :failed, linhas: { imported: 1, valid: 1 }, import_started_at: 1.hour.ago)
      parou.normalized_csv.attach(io: StringIO.new("row_number\n2\n"), filename: 'normalized.csv', content_type: 'text/csv')
      sem_arquivo = lista(situacao: :failed, linhas: { valid: 2 }, import_started_at: 1.hour.ago)
      com_falhas = lista(situacao: :completed_with_failures, linhas: { imported: 1, import_failed: 1 })

      listas

      por_id = response.parsed_body.index_by { |item| item['id'] }
      expect(por_id[desfeita.id]).to include('situacao' => 'desfeito', 'porcentagem' => 100, 'pode_tentar' => false)
      expect(por_id[desfazendo.id]).to include('situacao' => 'desfazendo', 'porcentagem' => 100, 'pode_tentar' => false)
      expect(por_id[parou.id]).to include('situacao' => 'falhou', 'porcentagem' => 50, 'pode_tentar' => true)
      expect(por_id[sem_arquivo.id]).to include('situacao' => 'falhou', 'porcentagem' => 0, 'pode_tentar' => false)
      expect(por_id[com_falhas.id]).to include('situacao' => 'pronto', 'porcentagem' => 100, 'pode_tentar' => false)
    end

    it 'faz o mesmo número de consultas com 3 e com 10 listas' do
      montar = lambda do |quantas|
        quantas.times do |vez|
          trazendo = vez.even?
          feita = lista(situacao: trazendo ? :importing : :failed, linhas: { imported: 2, valid: 2 }, import_started_at: 1.hour.ago)
          feita.normalized_csv.attach(io: StringIO.new("row_number\n2\n"), filename: 'normalized.csv', content_type: 'text/csv')
        end
      end
      montar.call(3)
      listas
      com_tres = consultas_feitas { listas }
      expect(response.parsed_body.size).to eq(3)

      montar.call(7)
      com_dez = consultas_feitas { listas }

      expect(response.parsed_body.size).to eq(10)
      expect(response.parsed_body.pluck('porcentagem').uniq).to eq([50])
      expect(com_dez).to eq(com_tres)
    end
  end

  describe 'GET listas/:id/andamento' do
    it 'conta pelas linhas: 0, 50 e 100 por cento' do
      entrando = lista(situacao: :importing, linhas: { valid: 4 }, import_started_at: 1.minute.ago)

      andamento(entrando)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('porcentagem' => 0, 'situacao' => 'trazendo', 'total' => 4, 'novas' => 0, 'completadas' => 0)

      entrando.campaign_import_rows.order(:row_number).limit(2).each_with_index do |linha, vez|
        linha.update!(status: vez.zero? ? :imported : :import_failed, was_existing_contact: vez.zero?)
      end
      andamento(entrando)

      expect(response.parsed_body).to eq('porcentagem' => 50, 'situacao' => 'trazendo', 'total' => 4, 'novas' => 0, 'completadas' => 1)

      entrando.campaign_import_rows.status_valid.find_each { |linha| linha.update!(status: :imported) }
      entrando.update!(status: :completed_with_failures)
      andamento(entrando)

      expect(response.parsed_body).to eq('porcentagem' => 100, 'situacao' => 'pronto', 'total' => 4, 'novas' => 2, 'completadas' => 1)
    end

    it 'diz que a lista parou onde parou' do
      parou = lista(situacao: :failed, linhas: { imported: 1, valid: 3 }, import_started_at: 1.hour.ago)

      andamento(parou)

      expect(response.parsed_body).to include('porcentagem' => 25, 'situacao' => 'falhou', 'total' => 4)
    end

    it 'responde 404 para o rascunho, a lista de outra conta e a da automação' do
      [lista(situacao: :ready_to_confirm), lista(conta: create(:account)),
       lista(opcoes: { 'origem' => CampaignImport::AUTOMATION_ORIGIN })].each do |de_fora|
        andamento(de_fora)

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end

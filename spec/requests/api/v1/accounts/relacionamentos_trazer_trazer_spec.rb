require 'rails_helper'

# #2896 — "Trazer minha lista" (Fatia 2), a conferência: o "Trazer" (o clique, o job que fecha a conferência e a
# gravação) e quem pode entrar em cada rota.
RSpec.describe 'Trazer minha lista: trazer e quem pode entrar (Relacionamentos)', :aggregate_failures, type: :request do
  include_context 'with trazer conferencia'

  let(:valores_da_planilha) { %w[11987650001 11987650002 11987650004 11987650005 ana.albuquerino davi.dornelino 2345-678] }

  describe 'POST leituras/:id/trazer' do
    it 'só confere e põe o fechamento na fila; o job fecha a conferência e a lista entra sem as deixadas nem as abertas' do
      importacao = ler_planilha(com_problemas)
      consertar(importacao, 4, valor: '11987650004')
      consertar(importacao, 5, valor: 'davi@exemplo.com.br')
      deixar_de_fora(importacao, 5)
      consertar(importacao, 6, valor: 'Fabio Ferreirinho')
      reabrir(importacao, 6)
      consertar(importacao, 8, ficar_com: 8)

      expect { trazer(importacao) }.to have_enqueued_job(ContactImports::Trazer::FecharConferenciaJob).with(importacao).once

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('trazidaId' => importacao.id)
      # A requisição não mexe no arquivo conferido nem nas linhas: isso é do job.
      expect(importacao.reload).to have_attributes(status: 'confirmed', valid_rows: 2, invalid_rows: 5)
      expect(importacao.confirmed_at).to be_present
      expect(conferido(importacao).pluck(:row_number)).to eq([2, 3])
      get "#{base}/listas/#{importacao.id}/andamento", headers: cabecalhos(admin)
      expect(response.parsed_body).to include('situacao' => 'trazendo')

      expect { perform_enqueued_jobs(only: ContactImports::Trazer::FecharConferenciaJob) }
        .to have_enqueued_job(CampaignImports::ImportJob).with(importacao).once

      expect(importacao.reload).to have_attributes(status: 'queued', total_rows: 7, valid_rows: 3, invalid_rows: 4)
      expect(conferido(importacao)).to eq(
        [{ row_number: 3, name: 'Bruno Brandolim', phone_number: '+5511987650002', email: nil },
         { row_number: 4, name: 'Carla Carvalhedo', phone_number: '+5511987650004', email: nil },
         { row_number: 8, name: 'Ana Outra', phone_number: '+5511987650001', email: nil }]
      )
      expect(importacao.campaign_import_rows.order(:row_number).pluck(:row_number, :status, :error_messages)).to eq(
        [[2, 'invalid', ['left_out']], [3, 'valid', []], [4, 'valid', []], [5, 'invalid', ['invalid_email']], [6, 'invalid', ['blank_name']],
         [7, 'invalid', ['missing_contact']], [8, 'valid', []]]
      )
      linhas = importacao.campaign_import_rows.map { |linha| linha.attributes.except('raw_name', 'normalized_name') }
      expect([linhas, importacao.options, importacao.validation_summary].to_json).not_to include('987650004', *valores_da_planilha)

      perform_enqueued_jobs(only: CampaignImports::ImportJob)

      expect(importacao.reload).to be_completed
      expect(account.contacts.order(:name).pluck(:name, :phone_number, :custom_attributes)).to eq(
        [['Ana Outra', '+5511987650001', {}], ['Bruno Brandolim', '+5511987650002', { 'plano' => 'Prata' }],
         ['Carla Carvalhedo', '+5511987650004', { 'plano' => 'Bronze' }]]
      )
      get "#{base}/listas/#{importacao.id}/andamento", headers: cabecalhos(admin)
      expect(response.parsed_body).to eq('porcentagem' => 100, 'situacao' => 'pronto', 'total' => 3, 'novas' => 3, 'completadas' => 0)
    end

    it 'o segundo clique responde o mesmo e não enfileira outro job' do
      importacao = ler_planilha(com_problemas)

      expect do
        trazer(importacao)
        trazer(importacao)
      end.to have_enqueued_job(ContactImports::Trazer::FecharConferenciaJob).once

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('trazidaId' => importacao.id)
    end

    it 'o job repetido não fecha a conferência duas vezes nem põe a gravação na fila de novo' do
      importacao = ler_planilha(com_problemas)
      consertar(importacao, 4, valor: '11987650004')
      consertar(importacao, 8, ficar_com: 8)
      trazer(importacao)

      expect { 2.times { ContactImports::Trazer::FecharConferenciaJob.perform_now(importacao) } }
        .to have_enqueued_job(CampaignImports::ImportJob).with(importacao).once

      expect(importacao.reload).to have_attributes(status: 'queued', valid_rows: 3, invalid_rows: 4)
      expect(conferido(importacao).pluck(:row_number)).to eq([3, 4, 8])

      # Com a gravação já feita, outro job repetido não desfaz nada.
      perform_enqueued_jobs(only: CampaignImports::ImportJob)
      expect { ContactImports::Trazer::FecharConferenciaJob.perform_now(importacao) }.not_to have_enqueued_job(CampaignImports::ImportJob)
      expect(importacao.reload).to be_completed
      expect(account.contacts.count).to eq(3)
    end

    it 'o job de fechar se perdeu: a varredura das importações paradas o põe de volta na fila e a lista entra' do
      importacao = ler_planilha(com_problemas)
      consertar(importacao, 4, valor: '11987650004')
      trazer(importacao)
      clear_enqueued_jobs

      travel_to((CampaignImports::Config.stalled_import_after + 1.minute).from_now) do
        expect { CampaignImports::StalledImportsJob.perform_now }
          .to have_enqueued_job(ContactImports::Trazer::FecharConferenciaJob).with(importacao).once
        gravar_a_lista
      end

      expect(importacao.reload).to be_completed
      expect(account.contacts.pluck(:phone_number)).to contain_exactly('+5511987650001', '+5511987650002', '+5511987650004')
      get "#{base}/listas/#{importacao.id}/andamento", headers: cabecalhos(admin)
      expect(response.parsed_body).to include('situacao' => 'pronto', 'total' => 3)
    end

    it 'o job de fechar não faz nada na leitura que a pessoa ainda não mandou trazer' do
      importacao = ler_planilha(com_problemas)
      consertar(importacao, 4, valor: '11987650004')

      expect { ContactImports::Trazer::FecharConferenciaJob.perform_now(importacao) }.not_to have_enqueued_job(CampaignImports::ImportJob)

      expect(importacao.reload).to have_attributes(status: 'ready_to_confirm', valid_rows: 2)
      expect(conferido(importacao).pluck(:row_number)).to eq([2, 3])
    end

    it 'recusa enquanto a planilha é lida, a leitura que falhou e a lista sem ninguém para entrar' do
      importacao = ler_planilha(com_problemas)
      importacao.update!(status: :validating)
      expect { trazer(importacao) }.not_to have_enqueued_job(ContactImports::Trazer::FecharConferenciaJob)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'leitura_nao_pronta')

      importacao.update!(status: :validation_failed)
      trazer(importacao)
      expect(response.parsed_body).to eq('error' => 'leitura_nao_pronta')

      # Passado o prazo do arquivo conferido não há mais de onde tirar quem entra.
      esquecida = ler_planilha(com_problemas)
      travel_to((CampaignImports::Config.generated_file_retention + 1.hour).from_now) do
        perform_enqueued_jobs(only: ActiveStorage::PurgeJob) { CampaignImports::PurgeExpiredFilesJob.perform_now }
      end
      expect { trazer(esquecida) }.not_to have_enqueued_job(ContactImports::Trazer::FecharConferenciaJob)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'nada_para_trazer')
      expect(esquecida.reload).to be_ready_to_confirm
    end
  end

  describe 'quem pode entrar' do
    def cada_rota(importacao, quem)
      {
        'PATCH respostas' => -> { responder(importacao, quem: quem, clientes: 'sim_todas') },
        'PATCH linhas/:linha' => -> { consertar(importacao, 4, quem: quem, valor: '11987650004') },
        'POST linhas/:linha/deixar_de_fora' => -> { deixar_de_fora(importacao, 4, quem: quem) },
        'POST linhas/:linha/reabrir' => -> { reabrir(importacao, 4, quem: quem) },
        'POST trazer' => -> { trazer(importacao, quem: quem) }
      }
    end

    def expect_recusadas(importacao, quem, estado)
      cada_rota(importacao, quem).each do |nome, pedir|
        pedir.call

        expect(response).to have_http_status(estado), nome
      end
      expect(importacao.reload).to have_attributes(status: 'ready_to_confirm', options: include('trazer' => {}))
    end

    it 'responde 401 sem login e ao agente sem a permissão de importar contatos' do
      importacao = ler_planilha(com_problemas)

      patch "#{base}/leituras/#{importacao.id}/respostas", params: { clientes: 'sim_todas' }, as: :json
      expect(response).to have_http_status(:unauthorized)
      patch "#{base}/leituras/#{importacao.id}/linhas/4", params: { valor: '11987650004' }, as: :json
      expect(response).to have_http_status(:unauthorized)
      post "#{base}/leituras/#{importacao.id}/linhas/4/deixar_de_fora"
      expect(response).to have_http_status(:unauthorized)
      post "#{base}/leituras/#{importacao.id}/linhas/4/reabrir"
      expect(response).to have_http_status(:unauthorized)
      post "#{base}/leituras/#{importacao.id}/trazer"
      expect(response).to have_http_status(:unauthorized)

      [agente, agente(permissoes: ['contact_view'])].each { |pessoa| expect_recusadas(importacao, pessoa, :unauthorized) }
    end

    it 'responde 404 com a chave da conta desligada' do
      importacao = ler_planilha(com_problemas)
      account.disable_features!('relacionamentos_novo')

      expect_recusadas(importacao, admin, :not_found)
    end

    it 'responde 404 para a leitura de outra conta, para a importação da tela antiga e para a da automação' do
      outra_conta = create(:account)
      outra_conta.enable_features!('relacionamentos_novo')
      de_fora = create(:user, account: outra_conta, role: :administrator)
      importacao = ler_planilha(com_problemas)

      cada_rota(importacao, de_fora).each_value do |pedir|
        # Quem é de outra conta pede pela conta dele: a leitura não é achada.
        pedir.call
        expect(response).to have_http_status(:unauthorized)
      end
      base_da_outra = "/api/v1/accounts/#{outra_conta.id}/relacionamentos/trazer"
      post "#{base_da_outra}/leituras/#{importacao.id}/trazer", headers: cabecalhos(de_fora)
      expect(response).to have_http_status(:not_found)
      patch "#{base_da_outra}/leituras/#{importacao.id}/linhas/4", params: { valor: '11987650004' }, headers: cabecalhos(de_fora), as: :json
      expect(response).to have_http_status(:not_found)

      # A importação da tela antiga (sem a marca) e a do passo "para cada item" da Automação, como cada uma nasce.
      post "/api/v1/accounts/#{account.id}/contact_imports", params: { import_file: arquivo(com_problemas) }, headers: cabecalhos(admin)
      expect(response).to have_http_status(:created)
      da_tela_antiga = account.campaign_imports.order(:id).last
      da_automacao = account.campaign_imports.create!(
        user: admin, status: :importing, mode: 'single_label', batch_count: 1,
        options: { flow: CampaignImport::CONTACTS_FLOW, origem: CampaignImport::AUTOMATION_ORIGIN }
      )
      [da_tela_antiga, da_automacao].each do |de_outra_tela|
        cada_rota(de_outra_tela, admin).each do |nome, pedir|
          pedir.call
          expect(response).to have_http_status(:not_found), nome
        end
      end
    end

    it 'atende a função com contact_manage' do
      importacao = ler_planilha(com_problemas)
      pessoa = agente(permissoes: ['contact_manage'])

      deixar_de_fora(importacao, 7, quem: pessoa)
      expect(response).to have_http_status(:ok)
      trazer(importacao, quem: pessoa)
      expect(response).to have_http_status(:ok)
    end

    describe 'com a importação por planilha desligada na instalação' do
      it 'responde 404' do
        importacao = ler_planilha(com_problemas)

        with_modified_env('CAMPAIGN_IMPORT_ENABLED' => 'false') { expect_recusadas(importacao, admin, :not_found) }
      end
    end
  end

  # Rodada 5: depois do prazo da planilha original os arquivos da conferência somem, mas o arquivo conferido ainda
  # vive. A lista que ainda não foi trazida não pode mais ser: entraria sem os consertos e com outra contagem.
  describe 'a conferência vencida' do
    let(:prazo) { CampaignImports::Config.original_file_retention }

    def vencer(importacao, idade: prazo + 1.minute)
      importacao.update_columns(created_at: idade.ago) # rubocop:disable Rails/SkipsModelValidations
      importacao
    end

    def confirmar_pela_rota_antiga(importacao)
      post "/api/v1/accounts/#{account.id}/contact_imports/#{importacao.id}/confirm", headers: cabecalhos(admin)
    end

    it 'a leitura responde "vencida" e toda escrita é recusada, a rota antiga de confirmar inclusive' do
      importacao = ler_planilha(com_problemas)
      consertar(importacao, 4, valor: '11987650004')
      vencer(importacao)

      expect(ler(importacao)).to eq('id' => importacao.id, 'situacao' => 'vencida')
      expect(response).to have_http_status(:ok)

      escritas = {
        'respostas' => -> { responder(importacao, clientes: 'sim_todas') },
        'colunas' => -> { trocar(importacao, 3, destino: 'cidade') },
        'colunas que leem de novo' => -> { trocar(importacao, 3, destino: 'telefone') },
        'consertar' => -> { consertar(importacao, 5, valor: 'davi@exemplo.com.br') },
        'deixar de fora' => -> { deixar_de_fora(importacao, 5) },
        'reabrir' => -> { reabrir(importacao, 4) },
        'trazer' => -> { trazer(importacao) },
        'confirmar pela rota antiga' => -> { confirmar_pela_rota_antiga(importacao) }
      }
      escritas.each do |nome, pedir|
        expect(&pedir).not_to have_enqueued_job, nome
        expect(response).to have_http_status(:unprocessable_entity), nome
        expect(response.parsed_body).to eq({ 'error' => 'conferencia_vencida' }), nome
      end
      expect(importacao.reload).to have_attributes(status: 'ready_to_confirm', options: include('trazer' => {}))
      expect(consertos(importacao).keys).to eq([4])
      expect(account.contacts.count).to eq(0)
    end

    it 'não aparece no histórico, e a lista que ainda está no prazo segue valendo' do
      vencida = vencer(ler_planilha(com_problemas))
      no_prazo = vencer(ler_planilha(com_problemas), idade: prazo - 1.minute)

      get "#{base}/listas", headers: cabecalhos(admin)
      expect(response.parsed_body).to eq([])
      expect(ler(no_prazo)).to include('situacao' => 'pronta')
      trazer(no_prazo)
      expect(response).to have_http_status(:ok)
      expect(ler(vencida)).to eq('id' => vencida.id, 'situacao' => 'vencida')
    end

    it 'a leitura que ainda estava sendo lida ou que tinha falhado também responde "vencida"' do
      %i[uploaded validating validation_failed].each do |estado|
        importacao = vencer(ler_planilha(com_problemas))
        importacao.update!(status: estado)

        expect(ler(importacao)).to eq('id' => importacao.id, 'situacao' => 'vencida')
      end
    end

    it 'a lista que já foi trazida não vence: continua no histórico, e o segundo clique responde o mesmo' do
      importacao = ler_planilha(com_problemas)
      trazer(importacao)
      gravar_a_lista
      vencer(importacao)

      get "#{base}/listas", headers: cabecalhos(admin)
      expect(response.parsed_body.sole).to include('id' => importacao.id, 'situacao' => 'pronto')
      trazer(importacao)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('trazidaId' => importacao.id)
    end

    it 'a lista cujo fechamento desistiu e venceu não pode mais ser tentada de novo' do
      importacao = ler_planilha(com_problemas)
      trazer(importacao)
      importacao.reload.update!(status: :failed, validation_summary: importacao.validation_summary.merge('import_error' => 'fechamento'))
      vencer(importacao)

      get "#{base}/listas", headers: cabecalhos(admin)
      expect(response.parsed_body.sole).to include('id' => importacao.id, 'situacao' => 'falhou', 'pode_tentar' => false)
      expect { trazer(importacao) }.not_to have_enqueued_job
      expect(response.parsed_body).to eq('error' => 'conferencia_vencida')
      expect { confirmar_pela_rota_antiga(importacao) }.not_to have_enqueued_job
      expect(response.parsed_body).to eq('error' => 'conferencia_vencida')
      expect(importacao.reload).to be_failed
    end

    # Rodada 6: a lista mandada trazer no último dia do prazo não pode fechar sem os consertos.
    it 'os anexos da lista que está fechando ficam até o fechamento rodar; depois de fechada, somem' do
      apagar_os_vencidos = -> { perform_enqueued_jobs(only: ActiveStorage::PurgeJob) { CampaignImports::PurgeExpiredFilesJob.perform_now } }
      importacao = ler_planilha(com_problemas)
      consertar(importacao, 4, valor: '11987650004')
      trazer(importacao)
      vencer(importacao)

      apagar_os_vencidos.call

      expect(importacao.reload).to be_confirmed
      expect(importacao.consertos).to be_attached
      expect(importacao.linhas_com_problema).to be_attached

      perform_enqueued_jobs(only: ContactImports::Trazer::FecharConferenciaJob)
      expect(importacao.reload).to be_queued
      apagar_os_vencidos.call

      expect(importacao.reload.consertos).not_to be_attached
      expect(importacao.linhas_com_problema).not_to be_attached
      # A gravação não precisa mais deles: o conserto já está no arquivo conferido.
      perform_enqueued_jobs(only: CampaignImports::ImportJob)
      expect(importacao.reload).to be_completed
      expect(account.contacts.pluck(:phone_number)).to contain_exactly('+5511987650001', '+5511987650002', '+5511987650004')
    end
  end

  describe 'o que pode dar errado depois do clique' do
    def confirmar_pela_rota_antiga(importacao)
      post "/api/v1/accounts/#{account.id}/contact_imports/#{importacao.id}/confirm", headers: cabecalhos(admin)
    end

    # G2: a rota antiga de "Importar" não pula o fechamento da conferência.
    it 'a rota antiga de confirmar passa pelo mesmo "Trazer": o que a pessoa consertou entra' do
      importacao = ler_planilha(com_problemas)
      consertar(importacao, 4, valor: '11987650004')
      consertar(importacao, 8, ficar_com: 8)

      expect { confirmar_pela_rota_antiga(importacao) }.to have_enqueued_job(ContactImports::Trazer::FecharConferenciaJob).with(importacao).once

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to include('id' => importacao.id)
      expect(importacao.reload).to be_confirmed
      expect(CampaignImports::ImportJob).not_to have_been_enqueued
      gravar_a_lista
      expect(account.contacts.pluck(:name, :phone_number)).to contain_exactly(
        ['Bruno Brandolim', '+5511987650002'], ['Carla Carvalhedo', '+5511987650004'], ['Ana Outra', '+5511987650001']
      )
    end

    it 'a rota antiga recusa a leitura marcada que o "Trazer" recusaria' do
      importacao = ler_planilha(com_problemas)
      importacao.update!(status: :validating)

      expect { confirmar_pela_rota_antiga(importacao) }.not_to have_enqueued_job

      expect(response).to have_http_status(:unprocessable_entity)
      expect(importacao.reload).to be_validating
    end

    # F2: a rota antiga decide pela marca, que não muda, e não pelo estado lido antes da trava.
    it 'a rota antiga não manda gravar sem fechamento a leitura marcada que ficou pronta entre a busca e a trava' do
      importacao = ler_planilha(com_problemas)
      consertar(importacao, 4, valor: '11987650004')
      importacao.update!(status: :validating)
      # A leitura termina logo depois de a rota buscar a importação: quem olha o estado antes da trava vê o velho.
      terminou = false
      allow(Relacionamentos::Trazer::Trazer).to receive(:fecha?).and_wrap_original do |original, lida|
        resposta = original.call(lida)
        CampaignImport.where(id: lida.id).update_all(status: :ready_to_confirm) unless terminou # rubocop:disable Rails/SkipsModelValidations
        terminou = true
        resposta
      end

      expect { confirmar_pela_rota_antiga(importacao) }.not_to have_enqueued_job(CampaignImports::ImportJob)

      expect(importacao.reload).not_to be_queued
    end

    # F3: a trava da importação não espera o armazenamento.
    it 'o fechamento baixa o arquivo conferido e os consertos antes de travar a importação' do
      importacao = ler_planilha(com_problemas)
      consertar(importacao, 4, valor: '11987650004')
      trazer(importacao)
      com_transacao = []
      anotar = lambda do |classe, leitura|
        allow(classe).to receive(:new).and_wrap_original do |original, *argumentos|
          leitor = original.call(*argumentos)
          allow(leitor).to receive(leitura).and_wrap_original do |ler|
            com_transacao << ActiveRecord::Base.connection.current_transaction.joinable?
            ler.call
          end
          leitor
        end
      end
      anotar.call(ContactImports::Trazer::ArquivoConferido, :linhas)
      anotar.call(ContactImports::Trazer::Consertos, :ler)

      gravar_a_lista

      expect(com_transacao).to eq([false, false])
      expect(importacao.reload).to be_completed
      expect(account.contacts.pluck(:phone_number)).to contain_exactly('+5511987650001', '+5511987650002', '+5511987650004')
    end

    it 'o fechamento lê de novo, já sob a trava, se os arquivos mudaram depois de baixados' do
      importacao = ler_planilha(com_problemas)
      consertar(importacao, 4, valor: '11987650004')
      fechamento = ContactImports::Trazer::FecharConferencia.new(importacao.reload).preparar
      consertar(importacao, 5, valor: 'davi@exemplo.com.br')

      importacao.reload.with_lock { fechamento.call }

      expect(conferido(importacao).pluck(:row_number)).to eq([2, 3, 4, 5])
    end

    # M7: o fechamento que sempre quebra não fica em laço.
    it 'o fechamento que quebra três vezes vira "falhou" com "Tentar de novo"; tentar de novo fecha e grava' do
      importacao = ler_planilha(com_problemas)
      consertar(importacao, 4, valor: '11987650004')
      trazer(importacao)
      allow(ContactImports::Trazer::FecharConferencia).to receive(:new).and_raise(ArgumentError)
      fechar = -> { ContactImports::Trazer::FecharConferenciaJob.perform_now(importacao) }

      2.times { expect(&fechar).to raise_error(ArgumentError) }
      expect(importacao.reload).to be_confirmed
      expect(&fechar).to raise_error(ArgumentError)

      expect(importacao.reload).to be_failed
      expect(importacao.validation_summary).to include('import_error' => 'fechamento')
      expect(importacao.options['trazer']).to eq('fechamentos' => 3)
      expect(&fechar).not_to have_enqueued_job
      get "#{base}/listas", headers: cabecalhos(admin)
      expect(response.parsed_body.sole).to include('id' => importacao.id, 'situacao' => 'falhou', 'pode_tentar' => true)
      get "#{base}/listas/#{importacao.id}/andamento", headers: cabecalhos(admin)
      expect(response.parsed_body).to include('situacao' => 'falhou')

      allow(ContactImports::Trazer::FecharConferencia).to receive(:new).and_call_original
      expect { confirmar_pela_rota_antiga(importacao) }.to have_enqueued_job(ContactImports::Trazer::FecharConferenciaJob).with(importacao).once
      expect(response).to have_http_status(:ok)
      expect(importacao.reload).to be_confirmed
      gravar_a_lista
      expect(importacao.reload).to be_completed
      expect(account.contacts.count).to eq(3)
    end

    # F4: sem o arquivo conferido o fechamento não tem o que fechar. A lista falha ali mesmo, na primeira tentativa.
    it 'a lista confirmada cujo arquivo conferido foi apagado antes do job acaba como "falhou" no fechamento, sem ir para a gravação' do
      importacao = ler_planilha(com_problemas)
      trazer(importacao)
      importacao.reload.normalized_csv.purge

      expect { perform_enqueued_jobs(only: ContactImports::Trazer::FecharConferenciaJob) }.not_to have_enqueued_job(CampaignImports::ImportJob)

      expect(importacao.reload).to be_failed
      expect(importacao.validation_summary).to include('import_error' => 'fechamento')
      expect(account.contacts.count).to eq(0)
      get "#{base}/listas/#{importacao.id}/andamento", headers: cabecalhos(admin)
      expect(response.parsed_body).to include('situacao' => 'falhou')
    end

    it 'o mesmo quando o anexo existe e o arquivo não chegou ao armazenamento (o conferido ou os consertos)' do
      %i[normalized_csv consertos].each do |anexo|
        importacao = ler_planilha(com_problemas)
        consertar(importacao, 4, valor: '11987650004')
        trazer(importacao)
        perdido = importacao.reload.public_send(anexo).blob
        perdido.service.delete(perdido.key)

        expect { perform_enqueued_jobs(only: ContactImports::Trazer::FecharConferenciaJob) }.not_to have_enqueued_job(CampaignImports::ImportJob)

        expect(importacao.reload).to be_failed, anexo.to_s
        expect(importacao.validation_summary).to include('import_error' => 'fechamento')
      end
      expect(account.contacts.count).to eq(0)
    end
  end
end

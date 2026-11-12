require 'rails_helper'

# #2896 (fatia 3) — as rotas do "Desfazer" de uma lista trazida: a prévia (quantas pessoas saem, quantas ficam e em
# quantas algo volta ao que era) e o clique, que só marca a lista como "desfazendo" e põe o job na fila. As regras do que
# sai, fica e volta estão em spec/services/relacionamentos/trazer (desfazer_spec.rb e quem_fica_spec.rb).
RSpec.describe 'Trazer minha lista: desfazer (Relacionamentos)', :aggregate_failures, type: :request do
  include_context 'with lista trazida'

  let(:base) { "/api/v1/accounts/#{account.id}/relacionamentos/trazer" }
  let(:ligadas) { { 'CAMPAIGN_JOURNEY_ENABLED' => 'true', 'CAMPAIGN_IMPORT_ENABLED' => 'true' } }
  let(:variaveis) { ligadas }
  let(:job) { Relacionamentos::Trazer::DesfazerJob }

  around { |example| with_modified_env(variaveis) { example.run } }

  before { account.enable_features!('relacionamentos_novo') }

  def cabecalhos(quem)
    quem.create_new_auth_token
  end

  def pedir_previa(importacao, quem: user)
    get "#{base}/listas/#{importacao.id}/previa_do_desfazer", headers: cabecalhos(quem)
  end

  def pedir_desfazer(importacao, quem: user)
    post "#{base}/listas/#{importacao.id}/desfazer", headers: cabecalhos(quem)
  end

  def situacao_na_lista(importacao)
    get "#{base}/listas", headers: cabecalhos(user)
    response.parsed_body.find { |item| item['id'] == importacao.id }&.fetch('situacao')
  end

  def agente(permissoes: nil)
    quem = create(:user, account: account, role: :agent)
    quem.account_users.first.update!(custom_role: create(:custom_role, account: account, permissions: permissoes)) if permissoes
    quem
  end

  describe 'GET listas/:id/previa_do_desfazer' do
    it 'diz quantas pessoas saem, quantas ficam e em quantas algo volta ao que era, sem gravar nada' do
      importacao = trazer_lista

      pedir_previa(importacao)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('tira' => 1, 'ficam' => 0, 'devolve' => 2)

      # Alguém conversou com a Carla: ela fica.
      create(:conversation, account: account, contact: pessoa('Carla Carvalhedo'))
      pedir_previa(importacao)

      expect(response.parsed_body).to eq('tira' => 0, 'ficam' => 1, 'devolve' => 2)
      expect(importacao.reload.undo_status).to eq('pending')
      expect(account.contacts.count).to eq(3)
      expect(Relacionamentos::CampoPreenchido.pendentes.count).to eq(Relacionamentos::CampoPreenchido.count)
    end

    it 'recusa a lista que ainda está entrando' do
      importacao = trazer_lista
      importacao.update!(status: :importing)

      pedir_previa(importacao)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'nao_pode_desfazer')
    end

    it 'conta também a lista que quebrou no meio da gravação' do
      importacao = trazer_lista
      importacao.update!(status: :failed, import_started_at: 1.hour.ago)

      pedir_previa(importacao)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('tira' => 1, 'ficam' => 0, 'devolve' => 2)
    end
  end

  describe 'POST listas/:id/desfazer' do
    it 'marca a lista como "desfazendo" e põe o job na fila; o job tira, devolve e marca "desfeito"' do
      importacao = trazer_lista
      carla = pessoa('Carla Carvalhedo')

      expect { pedir_desfazer(importacao) }.to have_enqueued_job(job).with(importacao, user).once

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body).to eq('id' => importacao.id, 'situacao' => 'desfazendo')
      # A requisição não apaga nem devolve nada: isso é do job.
      expect(importacao.reload).to have_attributes(status: 'completed', undo_status: 'processing')
      expect(account.contacts.exists?(carla.id)).to be(true)
      expect(ana.reload.email).to eq('ana.albuquerino@exemplo.com.br')
      expect(situacao_na_lista(importacao)).to eq('desfazendo')

      perform_enqueued_jobs(only: job)

      expect(importacao.reload.undo_status).to eq('completed')
      expect(account.contacts.exists?(carla.id)).to be(false)
      expect(ana.reload).to have_attributes(email: nil, contact_type: 'lead', company_id: nil)
      expect(bruno.reload).to have_attributes(name: '', phone_number: nil)
      expect(situacao_na_lista(importacao)).to eq('desfeito')
    end

    it 'não enfileira de novo no segundo clique, nem depois de desfeita' do
      importacao = trazer_lista
      pedir_desfazer(importacao)

      expect { pedir_desfazer(importacao) }.not_to have_enqueued_job(job)
      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body).to eq('id' => importacao.id, 'situacao' => 'desfazendo')

      perform_enqueued_jobs(only: job)

      expect { pedir_desfazer(importacao) }.not_to have_enqueued_job(job)
      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body).to eq('id' => importacao.id, 'situacao' => 'desfeito')
    end

    it 'põe de volta na fila o desfazer que parou há mais tempo que o limite, uma vez só' do
      importacao = trazer_lista
      pedir_desfazer(importacao)

      travel_to(CampaignImports::Config.stalled_import_after.from_now + 1.minute) do
        expect { pedir_desfazer(importacao) }.to have_enqueued_job(job).with(importacao, user).once
        expect(response.parsed_body).to eq('id' => importacao.id, 'situacao' => 'desfazendo')
        expect { pedir_desfazer(importacao) }.not_to have_enqueued_job(job)
      end
    end

    it 'recusa com nao_pode_desfazer a lista que ainda está entrando' do
      importacao = trazer_lista
      [{ status: :confirmed }, { status: :queued }, { status: :importing }].each do |estado|
        importacao.update!(estado)

        expect { pedir_desfazer(importacao) }.not_to have_enqueued_job(job)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to eq('error' => 'nao_pode_desfazer')
      end
      expect(importacao.reload.undo_status).to eq('pending')
      expect(account.contacts.count).to eq(3)
    end

    it 'aceita a lista gravada com linhas que falharam e a que quebrou no meio da gravação' do
      [{ status: :completed_with_failures }, { status: :failed, import_started_at: 1.hour.ago }].each do |estado|
        importacao = trazer_lista
        importacao.update!(estado)

        expect { pedir_desfazer(importacao) }.to have_enqueued_job(job).once
        expect(response).to have_http_status(:accepted)
        expect(response.parsed_body).to eq('id' => importacao.id, 'situacao' => 'desfazendo')
      end
    end
  end

  describe 'quem pode entrar' do
    let(:rotas) do
      {
        'GET listas/:id/previa_do_desfazer' => ->(importacao, quem) { pedir_previa(importacao, quem: quem) },
        'POST listas/:id/desfazer' => ->(importacao, quem) { pedir_desfazer(importacao, quem: quem) }
      }
    end

    def nada_foi_desfeito(importacao)
      expect(importacao.reload.undo_status).to eq('pending')
      expect(account.contacts.count).to eq(3)
    end

    it 'responde 401 sem login' do
      importacao = trazer_lista

      get "#{base}/listas/#{importacao.id}/previa_do_desfazer"
      expect(response).to have_http_status(:unauthorized)
      post "#{base}/listas/#{importacao.id}/desfazer"
      expect(response).to have_http_status(:unauthorized)
      nada_foi_desfeito(importacao)
    end

    it 'recusa o agente sem a permissão de importar contatos' do
      importacao = trazer_lista
      [agente, agente(permissoes: ['contact_view']), agente(permissoes: ['campaign_manage'])].each do |quem|
        rotas.each do |nome, pedir|
          expect { pedir.call(importacao, quem) }.not_to have_enqueued_job(job)

          expect(response).to have_http_status(:unauthorized), nome
        end
      end
      nada_foi_desfeito(importacao)
    end

    it 'atende a função com contact_manage' do
      importacao = trazer_lista
      quem = agente(permissoes: ['contact_manage'])

      pedir_previa(importacao, quem: quem)
      expect(response).to have_http_status(:ok)

      expect { pedir_desfazer(importacao, quem: quem) }.to have_enqueued_job(job).with(importacao, quem).once
      expect(response).to have_http_status(:accepted)
    end

    it 'responde 404 com a chave da conta desligada' do
      importacao = trazer_lista
      account.disable_features!('relacionamentos_novo')

      rotas.each do |nome, pedir|
        pedir.call(importacao, user)

        expect(response).to have_http_status(:not_found), nome
      end
      nada_foi_desfeito(importacao)
    end

    describe 'com a importação por planilha desligada na instalação' do
      let(:variaveis) { ligadas.merge('CAMPAIGN_IMPORT_ENABLED' => 'false') }

      it 'responde 404' do
        importacao = trazer_lista

        rotas.each do |nome, pedir|
          pedir.call(importacao, user)

          expect(response).to have_http_status(:not_found), nome
        end
        nada_foi_desfeito(importacao)
      end
    end

    it 'responde 404 para a lista de outra conta, a da automação e o rascunho' do
      outra = create(:account)
      dono = create(:user, account: outra, role: :administrator)
      outra.enable_features!('companies', 'relacionamentos_novo')
      de_fora = trazer_lista(conta: outra, quem: dono)
      da_automacao = trazer_lista
      da_automacao.update!(options: da_automacao.options.merge('origem' => CampaignImport::AUTOMATION_ORIGIN))
      rascunho = trazer_lista("Nome,Celular\nDavi Dornelino,11987650004\n", trazer: {})
      rascunho.update!(status: :ready_to_confirm)

      [de_fora, da_automacao, rascunho].each do |importacao|
        rotas.each do |nome, pedir|
          expect { pedir.call(importacao, user) }.not_to have_enqueued_job(job)

          expect(response).to have_http_status(:not_found), nome
        end
      end
      expect([de_fora, da_automacao, rascunho].map { |importacao| importacao.reload.undo_status }.uniq).to eq(['pending'])
      expect(outra.contacts.count).to eq(3)
    end
  end
end

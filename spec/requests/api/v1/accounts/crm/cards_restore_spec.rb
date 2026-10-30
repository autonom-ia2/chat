require 'rails_helper'

# Arquivados e restaurar card (#2095, Parte B). Antes, o card arquivado só voltava pelo "reabrir" (close com
# result=reopen), sem lista dos arquivados nem endpoint próprio.
RSpec.describe 'CRM: restaurar card arquivado', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:second_stage) { create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta') }
  let(:contact) { create(:contact, account: account) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm" }

  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run }
  end

  def card_in(stage:, status: :open, contact: self.contact, title: 'Seguro auto')
    account.crm_cards.create!(pipeline: stage.pipeline, stage: stage, contact: contact, title: title, status: status)
  end

  def archive!(card, as: admin)
    delete "#{base}/cards/#{card.id}", headers: auth_headers(as), as: :json
    expect(response).to have_http_status(:ok)
  end

  describe 'POST /crm/cards/:id/restore' do
    it 'volta para a etapa onde estava, aberto, e registra o reabrir como restauração' do
      card = card_in(stage: second_stage)
      archive!(card)

      post "#{base}/cards/#{card.id}/restore", headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('payload', 'status')).to eq('open')
      card.reload
      expect([card.status, card.stage_id]).to eq(['open', second_stage.id])
      activity = card.activities.order(:id).last
      expect([activity.event_type, activity.payload['restored'], activity.actor_id]).to eq(['reopen', true, admin.id])
    end

    it 'recusa o card que não está arquivado' do
      card = card_in(stage: second_stage)

      post "#{base}/cards/#{card.id}/restore", headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('crm.card_restore_not_archived')
    end

    it 'recusa o card de funil arquivado: o funil volta antes' do
      card = card_in(stage: second_stage)
      archive!(card)
      pipeline.archived!

      post "#{base}/cards/#{card.id}/restore", headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('crm.card_restore_pipeline_archived')
      expect(card.reload.status).to eq('archived')
    end

    it 'avisa quando o cliente já voltou (outro card aberto do contato no funil) e restaura com force' do
      card = card_in(stage: second_stage)
      archive!(card)
      open_card = card_in(stage: pipeline_and_stage.last, title: 'Seguro auto (voltou)')

      post "#{base}/cards/#{card.id}/restore", headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['error']).to eq('crm.card_restore_conflict')
      expect(response.parsed_body['open_card']).to include(
        'id' => open_card.id, 'stage_id' => pipeline_and_stage.last.id, 'stage_name' => 'Novo Lead'
      )
      expect(card.reload.status).to eq('archived')
      expect(card.activities.where(event_type: 'reopen')).to be_empty

      post "#{base}/cards/#{card.id}/restore", params: { force: true }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(card.reload.status).to eq('open')
    end

    it 'card de outro contato ou de outro funil não conflita' do
      card = card_in(stage: second_stage)
      archive!(card)
      card_in(stage: pipeline_and_stage.last, contact: create(:contact, account: account))
      other_pipeline, other_stage = create_crm_pipeline(account: account, user: admin, name: 'Pós-venda')
      card_in(stage: other_stage)
      expect(other_pipeline).to be_active

      post "#{base}/cards/#{card.id}/restore", headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST /crm/cards/restore (vários)' do
    it 'restaura os arquivados e pula, com o motivo, o que não pode voltar' do
      restored = card_in(stage: second_stage, contact: create(:contact, account: account))
      conflicting = card_in(stage: second_stage)
      not_archived = card_in(stage: pipeline_and_stage.last, contact: create(:contact, account: account))
      [restored, conflicting].each { |card| archive!(card) }
      open_card = card_in(stage: pipeline_and_stage.last)

      post "#{base}/cards/restore", params: { ids: [restored.id, conflicting.id, not_archived.id, 0] },
                                    headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to eq(
        'restored' => [restored.id],
        # Em ordem de id (o lote trava os cards sempre na mesma ordem).
        'skipped' => [
          { 'id' => 0, 'error' => 'forbidden' },
          { 'id' => conflicting.id, 'error' => 'crm.card_restore_conflict', 'open_card_id' => open_card.id,
            'open_card' => { 'id' => open_card.id, 'title' => 'Seguro auto', 'stage_name' => 'Novo Lead' } },
          { 'id' => not_archived.id, 'error' => 'crm.card_restore_not_archived' }
        ]
      )
      expect([restored.reload.status, conflicting.reload.status]).to eq(%w[open archived])
    end

    it 'dois arquivados do mesmo contato: o segundo conflita com o primeiro que acabou de voltar' do
      first = card_in(stage: second_stage)
      second = card_in(stage: second_stage, title: 'Seguro auto 2')
      [first, second].each { |card| archive!(card) }

      post "#{base}/cards/restore", params: { ids: [first.id, second.id] }, headers: auth_headers(admin), as: :json

      expect(response.parsed_body['payload']).to eq(
        'restored' => [first.id],
        'skipped' => [{ 'id' => second.id, 'error' => 'crm.card_restore_conflict', 'open_card_id' => first.id,
                        'open_card' => { 'id' => first.id, 'title' => 'Seguro auto', 'stage_name' => 'Proposta' } }]
      )
    end

    it 'não toca card de outra conta' do
      other_account = create(:account)
      other_admin = create(:user, account: other_account, role: :administrator)
      _, other_stage = create_crm_pipeline(account: other_account, user: other_admin)
      foreign = other_account.crm_cards.create!(pipeline: other_stage.pipeline, stage: other_stage, title: 'Alheio', status: :archived)

      post "#{base}/cards/restore", params: { ids: [foreign.id] }, headers: auth_headers(admin), as: :json

      expect(response.parsed_body['payload']).to eq('restored' => [], 'skipped' => [{ 'id' => foreign.id, 'error' => 'forbidden' }])
      expect(foreign.reload.status).to eq('archived')
    end
  end

  # Card cujo dono saiu da conta antes de o Agents::DestroyJob soltar os cards: o modelo recusaria gravá-lo.
  describe 'dono que saiu da conta' do
    let(:gone) { create(:user, account: account, role: :agent) }

    def card_of_gone(title)
      account.crm_cards.create!(pipeline: pipeline, stage: second_stage, title: title, owner: gone,
                                contact: create(:contact, account: account)).tap do |card|
        card.update!(status: :archived)
      end
    end

    before { gone }

    it 'restaura um sem dono, e a atividade diz quem era' do
      card = card_of_gone('Do que saiu')
      AccountUser.where(account: account, user: gone).delete_all

      post "#{base}/cards/#{card.id}/restore", headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect([card.reload.status, card.owner_id]).to eq(['open', nil])
      expect(card.activities.where(event_type: 'reopen').last.payload).to include('restored' => true, 'dono_que_saiu_id' => gone.id)
    end

    it 'um card desses não derruba o lote dos outros' do
      broken = card_of_gone('Do que saiu')
      fine = card_in(stage: second_stage, contact: create(:contact, account: account))
      archive!(fine)
      AccountUser.where(account: account, user: gone).delete_all

      post "#{base}/cards/restore", params: { ids: [broken.id, fine.id] }, headers: auth_headers(admin), as: :json

      expect(response.parsed_body['payload']).to eq('restored' => [broken.id, fine.id], 'skipped' => [])
    end
  end

  # O reabrir antigo (/close result=reopen e o lote com status=open) não pode restaurar sem as regras do restaurar.
  # Só com a flag crm_arquivados: sem ela, a janela antiga reabre como antes.
  describe 'reabrir o arquivado pelo fechar' do
    before { account.enable_features!(:crm_arquivados) }

    it 'sem a flag, o /close reabre como antes, sem a conferência do cliente que já voltou' do
      account.disable_features!(:crm_arquivados)
      card = card_in(stage: second_stage)
      archive!(card)
      card_in(stage: pipeline_and_stage.last, title: 'Voltou')

      post "#{base}/cards/#{card.id}/close", params: { result: 'reopen' }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(card.reload.status).to eq('open')
      expect(card.activities.where(event_type: 'reopen').last.payload).not_to include('restored' => true)
    end

    it 'no /close, reabrir é restaurar: volta para a etapa e registra como restauração' do
      card = card_in(stage: second_stage)
      archive!(card)

      post "#{base}/cards/#{card.id}/close", params: { result: 'reopen' }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect([card.reload.status, card.stage_id]).to eq(['open', second_stage.id])
      expect(card.activities.where(event_type: 'reopen').last.payload).to include('restored' => true)
    end

    it 'no /close, recusa o card de funil arquivado e avisa o cliente que já voltou' do
      card = card_in(stage: second_stage)
      archive!(card)
      open_card = card_in(stage: pipeline_and_stage.last, title: 'Voltou')

      post "#{base}/cards/#{card.id}/close", params: { result: 'open' }, headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body.dig('open_card', 'id')).to eq(open_card.id)

      open_card.update!(status: :lost)
      create_crm_pipeline(account: account, user: admin, name: 'Outro')
      pipeline.archived!
      post "#{base}/cards/#{card.id}/close", params: { result: 'reopen' }, headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('crm.card_restore_pipeline_archived')
      expect(card.reload.status).to eq('archived')
    end

    it 'no /close, ganhar ou perder o arquivado é recusado: restaure antes' do
      card = card_in(stage: second_stage)
      archive!(card)

      post "#{base}/cards/#{card.id}/close", params: { result: 'won' }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('crm.card_close_archived')
      expect(card.reload.status).to eq('archived')
    end

    it 'no lote, "Aberto" restaura com as recusas do restaurar, e ganho é recusado' do
      restored = card_in(stage: second_stage)
      conflicting = card_in(stage: second_stage, title: 'Do mesmo contato')
      won = card_in(stage: second_stage, contact: create(:contact, account: account), title: 'Pediu ganho')
      [restored, conflicting, won].each { |card| archive!(card) }

      post "#{base}/cards/bulk", params: { ids: [restored.id, conflicting.id], bulk_action: 'status', payload: { result: 'open' } },
                                 headers: auth_headers(admin), as: :json
      expect(response.parsed_body['payload']).to eq(
        'updated' => [restored.id], 'failed' => [{ 'id' => conflicting.id, 'error' => 'crm.card_restore_conflict' }]
      )

      post "#{base}/cards/bulk", params: { ids: [won.id], bulk_action: 'status', payload: { result: 'won' } },
                                 headers: auth_headers(admin), as: :json
      expect(response.parsed_body.dig('payload', 'failed')).to eq([{ 'id' => won.id, 'error' => 'crm.card_close_archived' }])
      expect([restored.reload.status, conflicting.reload.status, won.reload.status]).to eq(%w[open archived archived])
      expect(restored.activities.where(event_type: 'reopen').last.payload).to include('restored' => true)
    end
  end

  describe 'GET /crm/cards/archived' do
    let(:agent) { create(:user, account: account, role: :agent) }

    it 'lista os arquivados do funil, do mais recente, com quem arquivou e o motivo da IA' do
      by_person = card_in(stage: second_stage, title: 'Arquivado pela pessoa')
      by_ai = card_in(stage: pipeline_and_stage.last, title: 'Arquivado pela IA')
      card_in(stage: second_stage, title: 'Ainda aberto')
      travel_to(2.days.ago) { archive!(by_person) }
      by_ai.update!(status: :archived)
      Crm::ActivityLogger.new(card: by_ai, actor: nil, event_type: 'archive', payload: { by: 'ai', motivo: 'nao_e_negocio' }).perform

      get "#{base}/cards/archived", params: { pipeline_id: pipeline.id }, headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      rows = response.parsed_body['payload']
      expect(rows.pluck('id')).to eq([by_ai.id, by_person.id])
      expect(rows.first).to include('archived_by' => { 'type' => 'ai' }, 'archive_reason' => 'nao_e_negocio', 'can_restore' => true,
                                    'stage' => { 'id' => pipeline_and_stage.last.id, 'name' => 'Novo Lead' })
      expect(rows.last['archived_by']).to eq('type' => 'user', 'id' => admin.id, 'name' => admin.name)
      expect(rows.last['pipeline']).to eq('id' => pipeline.id, 'name' => pipeline.name, 'status' => 'active')
      expect(response.parsed_body['meta']).to eq('count' => 2, 'page' => 1, 'per_page' => 25)
    end

    it 'busca pelo título e pagina' do
      3.times { |index| archive!(card_in(stage: second_stage, title: "Renovação #{index}", contact: create(:contact, account: account))) }
      archive!(card_in(stage: second_stage, title: 'Outro assunto', contact: create(:contact, account: account)))

      get "#{base}/cards/archived", params: { pipeline_id: pipeline.id, search: 'renova', per_page: 2, page: 2 },
                                    headers: auth_headers(admin)

      expect(response.parsed_body['payload'].size).to eq(1)
      expect(response.parsed_body['meta']).to eq('count' => 3, 'page' => 2, 'per_page' => 2)
    end

    it 'sem funil, procura em todos, inclusive no funil arquivado' do
      _, other_stage = create_crm_pipeline(account: account, user: admin, name: 'Antigo')
      old = card_in(stage: other_stage, contact: create(:contact, account: account))
      archive!(old)
      archive!(card_in(stage: second_stage))
      other_stage.pipeline.archived!

      get "#{base}/cards/archived", headers: auth_headers(admin)

      expect(response.parsed_body['payload'].pluck('id')).to include(old.id)
      expect(response.parsed_body['meta']['count']).to eq(2)
      row = response.parsed_body['payload'].find { |item| item['id'] == old.id }
      expect(row['pipeline']['status']).to eq('archived')
    end

    it 'traz o desfecho guardado, os retornos que pararam, o status e o contato' do
      won = card_in(stage: second_stage, title: 'Ganho e arquivado')
      won.update!(status: :won)
      archive!(won)
      with_reminder = card_in(stage: second_stage, contact: create(:contact, account: account), title: 'Com retorno')
      Crm::FollowUp.create!(account: account, card: with_reminder, created_by: admin, title: 'Ligar', due_at: 2.days.from_now,
                            timezone: 'America/Sao_Paulo', status: :pending)
      archive!(with_reminder)

      get "#{base}/cards/archived", params: { pipeline_id: pipeline.id }, headers: auth_headers(admin)

      rows = response.parsed_body['payload'].index_by { |row| row['id'] }
      expect(rows[won.id]).to include('status' => 'archived', 'desfecho' => 'won', 'retornos_parados' => 0, 'contact_id' => contact.id)
      expect(rows[won.id]['contact']).to eq('id' => contact.id, 'name' => contact.name)
      expect(rows[with_reminder.id]).to include('desfecho' => nil, 'retornos_parados' => 1)
    end

    it 'sem funil, traz também os cards guardados com um funil arquivado; com funil, só os arquivados' do
      other_pipeline, other_stage = create_crm_pipeline(account: account, user: admin, name: 'Antigo')
      kept_open = card_in(stage: other_stage, contact: create(:contact, account: account), title: 'Ficou aberto')
      kept_won = card_in(stage: other_stage, contact: create(:contact, account: account), title: 'Ficou ganho', status: :won)
      archived = card_in(stage: second_stage, title: 'Arquivado')
      archive!(archived)
      card_in(stage: second_stage, contact: create(:contact, account: account), title: 'Aberto em funil ativo')
      other_pipeline.archived!

      get "#{base}/cards/archived", headers: auth_headers(admin)

      rows = response.parsed_body['payload'].index_by { |row| row['id'] }
      expect(rows.keys).to contain_exactly(archived.id, kept_open.id, kept_won.id)
      expect(rows[kept_open.id]).to include('status' => 'open', 'archived_at' => nil, 'archived_by' => nil, 'can_restore' => false,
                                            'pipeline' => { 'id' => other_pipeline.id, 'name' => 'Antigo', 'status' => 'archived' })
      expect(response.parsed_body['meta']['count']).to eq(3)

      get "#{base}/cards/archived", params: { pipeline_id: other_pipeline.id }, headers: auth_headers(admin)

      expect(response.parsed_body['payload']).to be_empty
    end

    it 'agente vê só os arquivados das caixas dele' do
      inbox = create_crm_inbox(account: account, members: [agent])
      mine = account.crm_cards.create!(pipeline: pipeline, stage: second_stage, inbox: inbox, title: 'Da caixa', status: :archived)
      account.crm_cards.create!(pipeline: pipeline, stage: second_stage, inbox: create_crm_inbox(account: account, name: 'Outra'),
                                title: 'De outra caixa', status: :archived)

      get "#{base}/cards/archived", params: { pipeline_id: pipeline.id }, headers: auth_headers(agent)

      expect(response.parsed_body['payload'].pluck('id')).to eq([mine.id])
    end
  end
end

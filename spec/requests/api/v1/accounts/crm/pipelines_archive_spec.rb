require 'rails_helper'

# Arquivar e restaurar funil (#2095, Parte B). Antes: o funil arquivado sumia da lista sem jeito de voltar pela tela, e
# arquivar não dizia quantos cards abertos ficavam presos nele nem oferecia movê-los.
RSpec.describe 'CRM: arquivar e restaurar funil', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin, name: 'Pós-venda') }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:target_pipeline_and_stage) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:target_stage) { create_crm_stage(account: account, pipeline: target_pipeline_and_stage.first, name: 'Retomar') }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/pipelines" }

  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run }
  end

  # A conta sempre tem outro funil ativo: o último funil ativo não se arquiva (Parte A, #2091).
  before { target_pipeline_and_stage }

  def card(status: :open, title: 'Cliente')
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: title, status: status)
  end

  describe 'GET /crm/pipelines/:id/archive_preview' do
    it 'diz quantos cards abertos ficam e quais caixas criam card no funil' do
      2.times { card }
      card(status: :won)
      card(status: :archived)
      inbox = create_crm_inbox(account: account, name: 'WhatsApp Pós-venda')
      account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, auto_create_card: true)

      get "#{base}/#{pipeline.id}/archive_preview", headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to eq(
        'open_cards_count' => 2,
        'inboxes' => [{ 'id' => inbox.id, 'name' => 'WhatsApp Pós-venda', 'auto_create_card' => true }]
      )
    end

    it 'agente não vê' do
      get "#{base}/#{pipeline.id}/archive_preview", headers: auth_headers(agent)

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'DELETE /crm/pipelines/:id' do
    it 'sem destino, arquiva e diz quantos cards abertos ficaram no funil' do
      2.times { card }

      delete "#{base}/#{pipeline.id}", headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to include('status' => 'archived', 'open_cards_count' => 2, 'moved_cards_count' => 0)
    end

    it 'com destino, leva os abertos para a etapa de outro funil na mesma transação, e os fechados ficam' do
      open_one = card(title: 'Aberto 1')
      open_two = card(title: 'Aberto 2')
      won = card(status: :won, title: 'Ganho')
      archived = card(status: :archived, title: 'Arquivado')
      allow(Crm::Webhooks::Emitter).to receive(:emit)

      delete "#{base}/#{pipeline.id}", params: { move_to_stage_id: target_stage.id }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to include('status' => 'archived', 'open_cards_count' => 0, 'moved_cards_count' => 2)
      [open_one, open_two].each do |moved|
        moved.reload
        expect([moved.pipeline_id, moved.stage_id, moved.status]).to eq([target_stage.pipeline_id, target_stage.id, 'open'])
        activity = moved.activities.find_by!(event_type: 'move')
        expect(activity.payload).to include('from_pipeline_id' => pipeline.id, 'to_stage_id' => target_stage.id,
                                            'from_stage_name' => 'Novo Lead', 'to_stage_name' => 'Retomar',
                                            'motivo' => 'funil_arquivado')
        expect(activity.actor_id).to eq(admin.id)
      end
      expect([won.reload.pipeline_id, archived.reload.pipeline_id]).to eq([pipeline.id, pipeline.id])
      # Reorganizar funis não é o cliente avançando: nada de webhook nem conversão de anúncio por card movido.
      expect(Crm::Webhooks::Emitter).not_to have_received(:emit)
    end

    it 'recusa destino que não serve e não muda nada' do
      open_card = card
      same_pipeline_stage = create_crm_stage(account: account, pipeline: pipeline, name: 'Mesma')
      archived_pipeline, archived_stage = create_crm_pipeline(account: account, user: admin, name: 'Velho')
      archived_pipeline.archived!
      other_account = create(:account)
      foreign_stage = create_crm_pipeline(account: other_account, user: create(:user, account: other_account, role: :administrator)).last

      [same_pipeline_stage.id, archived_stage.id, foreign_stage.id, 0].each do |stage_id|
        delete "#{base}/#{pipeline.id}", params: { move_to_stage_id: stage_id }, headers: auth_headers(admin), as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('crm.pipeline_archive_invalid_target')
      end
      expect(pipeline.reload).to be_active
      expect(open_card.reload.pipeline_id).to eq(pipeline.id)
    end

    it 'se mover um card falha, o funil continua ativo e nenhum card muda' do
      first = card(title: 'Primeiro')
      second = card(title: 'Segundo')
      allow(Crm::Activity).to receive(:insert_all!).and_raise(ActiveRecord::StatementInvalid, 'falha')

      expect do
        Crm::Pipelines::Archiver.new(pipeline: pipeline, actor: admin, target_stage: target_stage).perform
      end.to raise_error(ActiveRecord::StatementInvalid)

      expect(pipeline.reload).to be_active
      expect([first.reload.pipeline_id, second.reload.pipeline_id]).to eq([pipeline.id, pipeline.id])
    end

    it 'no funil já arquivado, leva os cards que ficaram presos nele' do
      stuck = card
      pipeline.archived!

      delete "#{base}/#{pipeline.id}", params: { move_to_stage_id: target_stage.id }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(stuck.reload.stage_id).to eq(target_stage.id)
    end
  end

  describe 'funis arquivados e restaurar' do
    it 'lista os arquivados com os cards abertos que voltam, e a lista normal segue só com os ativos' do
      2.times { card }
      card(status: :won)
      target_pipeline_and_stage
      pipeline.archived!

      get base, params: { status: 'archived' }, headers: auth_headers(admin)

      expect(response.parsed_body['payload'].map { |item| item.slice('id', 'open_cards_count') })
        .to eq([{ 'id' => pipeline.id, 'open_cards_count' => 2 }])

      get base, headers: auth_headers(admin)

      expect(response.parsed_body['payload'].pluck('id')).to eq([target_pipeline_and_stage.first.id])
      expect(response.parsed_body['payload'].first).not_to have_key('open_cards_count')
    end

    it 'restaura o funil e os cards abertos voltam ao quadro com ele' do
      open_card = card
      pipeline.archived!

      post "#{base}/#{pipeline.id}/restore", headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to include('status' => 'active', 'open_cards_count' => 1)
      expect(pipeline.reload).to be_active

      get "/api/v1/accounts/#{account.id}/crm/kanban", params: { pipeline_id: pipeline.id }, headers: auth_headers(admin)

      expect(response.body).to include(%("id":#{open_card.id}))
    end

    it 'recusa restaurar funil ativo' do
      post "#{base}/#{pipeline.id}/restore", headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('crm.pipeline_restore_not_archived')
    end

    it 'agente não restaura' do
      pipeline.archived!

      post "#{base}/#{pipeline.id}/restore", headers: auth_headers(agent), as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(pipeline.reload).to be_archived
    end
  end
end

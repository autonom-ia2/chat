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
        'inboxes' => [{ 'id' => inbox.id, 'name' => 'WhatsApp Pós-venda', 'auto_create_card' => true, 'other_pipelines' => [] }],
        'follow_ups_count' => 0, 'follow_up_series_count' => 0, 'upcoming_meetings_count' => 0
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

    it 'com destino, diz quais clientes ficaram com dois cards abertos no destino (#2145)' do
      ana = account.contacts.create!(name: 'Ana')
      account.crm_cards.create!(pipeline: target_stage.pipeline, stage: target_stage, title: 'Outro assunto', contact: ana)
      movido = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Ana', contact: ana)
      card(title: 'Sem contato')

      delete "#{base}/#{pipeline.id}", params: { move_to_stage_id: target_stage.id }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('payload', 'clients_with_two_open'))
        .to eq('count' => 1, 'items' => [{ 'contact_id' => ana.id, 'name' => 'Ana', 'card_id' => movido.id }])
    end

    # #2145: em lotes, a recusa pode vir depois de um lote confirmado; a resposta diz quantos cards já foram.
    it 'destino arquivado entre dois lotes: recusa com quantos cards já foram (moved_count)' do
      stub_const('Crm::Pipelines::Archiver::LOTE', 1)
      create_crm_pipeline(account: account, user: admin, name: 'Terceiro')
      first = card(title: 'Primeiro')
      card(title: 'Segundo')
      card(title: 'Terceiro')
      destino = target_stage.pipeline
      allow(Crm::Activity).to receive(:insert_all!).and_wrap_original do |original, *args|
        original.call(*args).tap { Crm::Pipeline.where(id: destino.id).update_all(status: Crm::Pipeline.statuses[:archived]) } # rubocop:disable Rails/SkipsModelValidations
      end

      delete "#{base}/#{pipeline.id}", params: { move_to_stage_id: target_stage.id }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => Crm::Pipelines::Archiver::INVALID_TARGET, 'moved_count' => 1)
      expect(pipeline.reload).to be_active
      expect(first.reload.pipeline_id).to eq(destino.id)
      expect(pipeline.cards.open.count).to eq(2)
    end

    it 'recusa arquivar o último funil ativo pelo DELETE, como o PATCH (Parte A), e não move nada' do
      open_card = card
      target_pipeline_and_stage.first.archived!

      delete "#{base}/#{pipeline.id}", headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'crm.pipeline_archive_last_active',
                                              'message' => I18n.t('crm.pipelines.archive_last_active'))
      expect(pipeline.reload).to be_active
      expect(open_card.reload.pipeline_id).to eq(pipeline.id)
    end

    it 'card de dono que saiu da conta não trava o arquivar com mudança: vai sem dono' do
      gone = create(:user, account: account, role: :agent)
      moved = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Do que saiu', owner: gone)
      AccountUser.where(account: account, user: gone).delete_all

      delete "#{base}/#{pipeline.id}", params: { move_to_stage_id: target_stage.id }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect([moved.reload.stage_id, moved.owner_id]).to eq([target_stage.id, nil])
    end

    it 'guardar junto (stop_follow_ups), diz quantos retornos dos cards que ficaram pararam' do
      kept = card
      Crm::FollowUp.create!(account: account, card: kept, created_by: admin, title: 'Ligar', due_at: 2.days.from_now,
                            timezone: 'America/Sao_Paulo', status: :pending)

      delete "#{base}/#{pipeline.id}", params: { stop_follow_ups: true }, headers: auth_headers(admin), as: :json

      expect(response.parsed_body['payload']).to include('open_cards_count' => 1, 'stopped_follow_ups_count' => 1)
      expect(kept.follow_ups.first).to be_canceled
    end

    it 'sem destino e sem stop_follow_ups (janela antiga), arquiva como antes e os retornos seguem' do
      kept = card
      Crm::FollowUp.create!(account: account, card: kept, created_by: admin, title: 'Ligar', due_at: 2.days.from_now,
                            timezone: 'America/Sao_Paulo', status: :pending)

      delete "#{base}/#{pipeline.id}", headers: auth_headers(admin), as: :json

      expect(response.parsed_body['payload']).to include('open_cards_count' => 1, 'stopped_follow_ups_count' => 0)
      expect(kept.follow_ups.first).to be_pending
    end

    it 'no funil já arquivado, leva os cards que ficaram presos nele' do
      stuck = card
      pipeline.archived!

      delete "#{base}/#{pipeline.id}", params: { move_to_stage_id: target_stage.id }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(stuck.reload.stage_id).to eq(target_stage.id)
    end
  end

  describe 'DELETE /crm/pipelines/:id: caixas e funil principal (decisão 7)' do
    let(:target_pipeline) { target_pipeline_and_stage.first }
    let(:inbox) { create_crm_inbox(account: account, name: 'WhatsApp') }

    def link(pipeline, inbox, auto: true, default_stage: nil)
      account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, auto_create_card: auto, default_stage: default_stage)
    end

    it 'leva as ligações e o funil padrão da caixa para o destino, e diz quais caixas foram' do
      moved = link(pipeline, inbox, default_stage: stage)
      setting = account.crm_inbox_settings.create!(inbox: inbox, crm_enabled: true, auto_create_card: true,
                                                   default_pipeline: pipeline, default_stage: stage)
      first_target_stage = target_pipeline_and_stage.last
      target_stage

      delete "#{base}/#{pipeline.id}", params: { inboxes_to_pipeline_id: target_pipeline.id }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to include(
        'status' => 'archived', 'moved_inboxes' => [{ 'id' => inbox.id, 'name' => 'WhatsApp' }], 'inboxes_target_pipeline_id' => target_pipeline.id
      )
      expect([moved.reload.pipeline_id, moved.default_stage_id, moved.auto_create_card]).to eq([target_pipeline.id, nil, true])
      expect([setting.reload.default_pipeline_id, setting.default_stage_id]).to eq([target_pipeline.id, first_target_stage.id])
    end

    it 'caixa já ligada ao destino: fica a ligação do destino, criando se qualquer uma criava' do
      link(pipeline, inbox, auto: true)
      kept = link(target_pipeline, inbox, auto: false)

      delete "#{base}/#{pipeline.id}", params: { inboxes_to_pipeline_id: target_pipeline.id }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(account.crm_pipeline_inboxes.where(inbox: inbox).pluck(:id)).to eq([kept.id])
      expect(kept.reload.auto_create_card).to be(true)
    end

    it 'sem destino das caixas, as ligações ficam no funil arquivado e a resposta diz que nada foi' do
      kept = link(pipeline, inbox)

      delete "#{base}/#{pipeline.id}", headers: auth_headers(admin), as: :json

      expect(response.parsed_body['payload']).to include('moved_inboxes' => [], 'inboxes_target_pipeline_id' => nil)
      expect(kept.reload.pipeline_id).to eq(pipeline.id)
    end

    it 'recusa destino das caixas que não serve e não muda nada' do
      open_card = card
      moved = link(pipeline, inbox)
      archived_pipeline = create_crm_pipeline(account: account, user: admin, name: 'Velho').first
      archived_pipeline.archived!
      other_account = create(:account)
      foreign = create_crm_pipeline(account: other_account, user: create(:user, account: other_account, role: :administrator)).first

      [pipeline.id, archived_pipeline.id, foreign.id, 0].each do |pipeline_id|
        delete "#{base}/#{pipeline.id}", params: { inboxes_to_pipeline_id: pipeline_id, move_to_stage_id: target_stage.id },
                                         headers: auth_headers(admin), as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('crm.pipeline_archive_invalid_inboxes_target')
      end
      expect(pipeline.reload).to be_active
      expect(moved.reload.pipeline_id).to eq(pipeline.id)
      expect(open_card.reload.pipeline_id).to eq(pipeline.id)
    end

    it 'arquiva o único principal passando o principal para outro funil na mesma operação' do
      pipeline.update!(is_default: true)

      delete "#{base}/#{pipeline.id}", headers: auth_headers(admin), as: :json
      expect(response.parsed_body['error']).to eq('crm.pipeline_archive_only_default')

      delete "#{base}/#{pipeline.id}", params: { new_default_pipeline_id: target_pipeline.id }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect([pipeline.reload.status, pipeline.is_default, target_pipeline.reload.is_default]).to eq(['archived', false, true])
    end

    it 'recusa novo principal que não serve e não muda nada' do
      pipeline.update!(is_default: true)

      delete "#{base}/#{pipeline.id}", params: { new_default_pipeline_id: pipeline.id }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('crm.pipeline_archive_invalid_new_default')
      expect([pipeline.reload.status, pipeline.is_default, target_pipeline.reload.is_default]).to eq(['active', true, false])
    end

    it 'a prévia diz em que outro funil ativo a caixa continua criando card' do
      link(pipeline, inbox)
      link(target_pipeline, inbox)

      get "#{base}/#{pipeline.id}/archive_preview", headers: auth_headers(admin)

      expect(response.parsed_body.dig('payload', 'inboxes', 0, 'other_pipelines')).to eq([{ 'id' => target_pipeline.id, 'name' => 'Vendas' }])
    end
  end

  describe 'funis arquivados e restaurar' do
    it 'lista os arquivados com os cards abertos que voltam, e a lista normal segue só com os ativos' do
      2.times { card }
      card(status: :won)
      target_pipeline_and_stage
      inbox = create_crm_inbox(account: account, name: 'WhatsApp Pós-venda')
      account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, auto_create_card: true)
      account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: create_crm_inbox(account: account, name: 'Sem criar'))
      pipeline.archived!

      get base, params: { status: 'archived' }, headers: auth_headers(admin)

      expect(response.parsed_body['payload'].map { |item| item.slice('id', 'open_cards_count', 'cards_count', 'inboxes') })
        .to eq([{ 'id' => pipeline.id, 'open_cards_count' => 2, 'cards_count' => 3,
                  'inboxes' => [{ 'id' => inbox.id, 'name' => 'WhatsApp Pós-venda' }] }])

      get base, headers: auth_headers(admin)

      expect(response.parsed_body['payload'].pluck('id')).to eq([target_pipeline_and_stage.first.id])
      expect(response.parsed_body['payload'].first).not_to have_key('open_cards_count')
    end

    it 'para quem só vê o CRM, conta só os cards que a pessoa vê e não manda as caixas' do
      inbox = create_crm_inbox(account: account, name: 'WhatsApp Pós-venda', members: [agent])
      escondida = create_crm_inbox(account: account, name: 'Outra caixa')
      account.crm_cards.create!(pipeline: pipeline, stage: pipeline_and_stage.last, inbox: inbox, title: 'Visível')
      account.crm_cards.create!(pipeline: pipeline, stage: pipeline_and_stage.last, inbox: escondida, title: 'Escondido')
      account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, auto_create_card: true)
      target_pipeline_and_stage
      pipeline.archived!

      get base, params: { status: 'archived' }, headers: auth_headers(agent)

      expect(response.parsed_body['payload'].map { |item| item.slice('open_cards_count', 'cards_count', 'inboxes') })
        .to eq([{ 'open_cards_count' => 1, 'cards_count' => 1, 'inboxes' => [] }])
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

    it 'recusa arquivar de novo um funil já arquivado sem levar os cards (segundo clique)' do
      pipeline.archived!

      delete "#{base}/#{pipeline.id}", headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('crm.pipeline_archive_already_archived')
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

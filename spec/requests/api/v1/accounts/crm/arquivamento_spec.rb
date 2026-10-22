require 'rails_helper'

# Regras de arquivamento do CRM (Parte A): os caminhos da API para arquivar card, arquivar funil e apagar etapa.
RSpec.describe 'CRM arquivamento', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:funil) { create_crm_pipeline(account: account, user: admin) }
  let(:card) { account.crm_cards.create!(pipeline: funil.first, stage: funil.last, title: 'Pedido') }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  def lembrete
    Crm::FollowUp.create!(account: account, card: card, created_by: admin, title: 'Ligar', due_at: 2.days.from_now,
                          timezone: 'America/Sao_Paulo', status: :pending)
  end

  def sugestao
    account.crm_ai_stage_suggestions.create!(card: card, from_stage: card.stage, to_stage: card.stage, confidence: 0.9, model_used: 't')
  end

  describe 'arquivar card' do
    it 'pela tela, cancela os lembretes e expira as sugestões pendentes' do
      tarefa = lembrete
      pendente = sugestao

      delete "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}", headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(tarefa.reload).to be_canceled
      expect(pendente.reload).to be_expired
    end

    it 'em lote, cancela os lembretes e expira as sugestões pendentes' do
      tarefa = lembrete
      pendente = sugestao

      post "/api/v1/accounts/#{account.id}/crm/cards/bulk", params: { ids: [card.id], action_name: 'delete' }, headers: auth_headers(admin)

      expect(card.reload).to be_archived
      expect(tarefa.reload).to be_canceled
      expect(pendente.reload).to be_expired
    end
  end

  describe 'arquivar funil' do
    let(:url) { "/api/v1/accounts/#{account.id}/crm/pipelines/#{funil.first.id}" }

    it 'recusa o último funil ativo da conta, com a mensagem' do
      delete url, headers: auth_headers(admin)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'crm.pipeline_archive_last_active',
                                              'message' => I18n.t('crm.pipelines.archive_last_active'))
      expect(funil.first.reload).to be_active
    end

    it 'recusa o único principal ativo, também pelo PATCH de status' do
      funil.first.update!(is_default: true)
      create_crm_pipeline(account: account, user: admin, name: 'Pós-venda')

      delete url, headers: auth_headers(admin)
      expect(response.parsed_body['error']).to eq('crm.pipeline_archive_only_default')

      patch url, params: { pipeline: { status: 'archived' } }, headers: auth_headers(admin)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(funil.first.reload).to be_active
    end

    it 'recusa o último funil ativo também com o status em número (PATCH status: 1)' do
      patch url, params: { pipeline: { status: 1 } }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('crm.pipeline_archive_last_active')
      expect(funil.first.reload).to be_active
    end

    it 'desmarcar o principal no mesmo PATCH não libera arquivar o único principal' do
      funil.first.update!(is_default: true)
      create_crm_pipeline(account: account, user: admin, name: 'Pós-venda')

      patch url, params: { pipeline: { status: 'archived', is_default: false } }, headers: auth_headers(admin), as: :json

      expect(response.parsed_body['error']).to eq('crm.pipeline_archive_only_default')
      expect(funil.first.reload).to have_attributes(status: 'active', is_default: true)
    end

    it 'PATCH sem arquivar continua gravando o funil' do
      patch url, params: { pipeline: { name: 'Vendas novas' } }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(funil.first.reload.name).to eq('Vendas novas')
    end

    it 'arquiva quando outro funil ativo é o principal' do
      funil.first.update!(is_default: true)
      outro, = create_crm_pipeline(account: account, user: admin, name: 'Pós-venda')
      outro.update!(is_default: true)

      delete url, headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(funil.first.reload).to be_archived
    end
  end

  describe 'apagar etapa' do
    let(:destino) { create_crm_stage(account: account, pipeline: funil.first, name: 'Proposta') }

    it 'apaga a etapa cuja automação já rodou num card (antes respondia "ainda tem cards")' do
      vazia = create_crm_stage(account: account, pipeline: funil.first, name: 'Sem uso', position: 2)
      automacao = account.crm_stage_automations.create!(pipeline: funil.first, stage: vazia, name: 'Avisar', trigger_event: :on_enter)
      Crm::StageAutomationExecution.create!(account: account, card: card, stage_automation: automacao, trigger_token: 't1')

      delete "/api/v1/accounts/#{account.id}/crm/stages/#{vazia.id}", headers: auth_headers(admin)

      expect(response).to have_http_status(:no_content)
      expect(Crm::StageAutomationExecution.where(stage_automation_id: automacao.id)).to be_empty
    end

    it 'leva os cards para a etapa escolhida com a atividade, o nome das etapas e a nova entrada na etapa' do
      card.update!(entered_stage_at: 10.days.ago)
      outro = account.crm_cards.create!(pipeline: funil.first, stage: funil.last, title: 'Outro', status: :won)
      origem = funil.last

      delete "/api/v1/accounts/#{account.id}/crm/stages/#{origem.id}", params: { target_stage_id: destino.id }, headers: auth_headers(admin)

      expect(response).to have_http_status(:no_content)
      expect([card, outro].map { |item| item.reload.stage_id }).to eq([destino.id, destino.id])
      expect(outro).to be_won
      expect(card.entered_stage_at).to be_within(1.minute).of(Time.current)
      movimentos = Crm::Activity.where(card_id: [card.id, outro.id], event_type: 'move')
      expect(movimentos.count).to eq(2)
      expect(movimentos.first).to have_attributes(actor_type: 'user', actor_id: admin.id)
      expect(movimentos.first.payload).to include('from_stage_id' => origem.id, 'to_stage_id' => destino.id,
                                                  'from_stage_name' => 'Novo Lead', 'to_stage_name' => 'Proposta')
    end
  end

  describe 'relatórios' do
    it 'a lista de funis dos relatórios deixa de fora o funil arquivado' do
      arquivado, = create_crm_pipeline(account: account, user: admin, name: 'Antigo')
      arquivado.archived!
      funil

      get "/api/v1/accounts/#{account.id}/crm/reports/pipelines", headers: auth_headers(admin)

      expect(response.parsed_body['payload'].pluck('id')).to eq([funil.first.id])
    end
  end
end

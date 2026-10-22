require 'rails_helper'

# Excluir de vez (#2096, Parte C): card arquivado, funil arquivado e os cards do contato (LGPD). Só administrador, só o
# que já está arquivado, com a confirmação digitada; a conversa do cliente fica.
RSpec.describe 'CRM excluir de vez', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:contact) { account.contacts.create!(name: 'Cliente', phone_number: '+5511999990002') }
  let(:inbox) { create_crm_inbox(account: account) }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let(:base) { "/api/v1/accounts/#{account.id}" }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true') { example.run }
  end

  def card_arquivado(title: 'Pedido', status: :archived, **attrs)
    account.crm_cards.create!({ pipeline: pipeline, stage: stage, contact: contact, title: title, status: status }.merge(attrs))
  end

  def call(user, path, params = {})
    post path, params: params, headers: user.create_new_auth_token, as: :json
  end

  def auditorias
    Audited.audit_class.where(auditable: account, action: Crm::ExclusaoDefinitiva::ACAO)
  end

  describe 'POST crm/cards/permanent_delete' do
    let(:path) { "#{base}/crm/cards/permanent_delete" }

    it 'apaga o card arquivado e o histórico dele, deixa a conversa e grava a auditoria só com ids' do
      card = create_card_cheio(account: account, user: admin, pipeline: pipeline, contact: contact, conversation: conversation)
      message = create_incoming_message(conversation: conversation)

      call(admin, path, card_ids: [card.id], confirmation: ' EXCLUIR ')

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to eq('deleted_ids' => [card.id])
      expect(onde_o_card_ainda_aparece(card.id)).to eq([])
      expect(conversation.reload.messages.pluck(:id)).to include(message.id)
      expect(auditorias.sole).to have_attributes(user_id: admin.id,
                                                 audited_changes: { 'alvo' => 'cards', 'cards_apagados' => 1, 'card_ids' => [card.id] })
    end

    it 'apaga vários de uma vez' do
      cards = [card_arquivado(title: 'Um'), card_arquivado(title: 'Dois')]

      call(admin, path, card_ids: cards.map(&:id), confirmation: 'EXCLUIR')

      expect(response).to have_http_status(:ok)
      expect(Crm::Card.where(id: cards.map(&:id))).to be_empty
    end

    it 'recusa quem não é administrador (403) e não apaga' do
      card = card_arquivado

      call(agent, path, card_ids: [card.id], confirmation: 'EXCLUIR')

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq('crm.permanent_delete.admin_only')
      expect(card.reload).to be_present
    end

    it 'recusa card que não está arquivado (422), e o pedido inteiro com ele' do
      arquivado = card_arquivado
      aberto = card_arquivado(title: 'Aberto', status: :open)
      ganho = card_arquivado(title: 'Ganho', status: :won)

      call(admin, path, card_ids: [arquivado.id, aberto.id, ganho.id], confirmation: 'EXCLUIR')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'crm.permanent_delete.not_archived', 'card_ids' => [aberto.id, ganho.id].sort)
      expect(Crm::Card.where(id: [arquivado.id, aberto.id, ganho.id]).count).to eq(3)
    end

    it 'recusa confirmação errada (422)' do
      card = card_arquivado

      %w[excluir APAGAR].push('').each do |confirmation|
        call(admin, path, card_ids: [card.id], confirmation: confirmation)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('crm.permanent_delete.confirmation_mismatch')
      end
      expect(card.reload).to be_present
    end

    it 'não acha card de outra conta (404)' do
      outra = create(:account)
      outro_admin = create(:user, account: outra, role: :administrator)
      alheio = outra.crm_cards.create!(pipeline: create_crm_pipeline(account: outra, user: outro_admin).first,
                                       stage: outra.crm_pipeline_stages.first, title: 'Alheio', status: :archived)

      call(admin, path, card_ids: [alheio.id], confirmation: 'EXCLUIR')

      expect(response).to have_http_status(:not_found)
      expect(alheio.reload).to be_present
    end

    it 'recusa pedido vazio ou grande demais' do
      call(admin, path, card_ids: ['x'], confirmation: 'EXCLUIR')
      expect(response.parsed_body['error']).to eq('crm.permanent_delete.no_cards')

      call(admin, path, card_ids: (1..101).to_a, confirmation: 'EXCLUIR')
      expect(response.parsed_body).to eq('error' => 'crm.permanent_delete.too_many_cards', 'max' => 100)
    end

    it 'não apaga nada quando a reunião futura não cancela no calendário (422)' do
      card = card_arquivado
      meeting = create_reuniao(account: account, card: card, user: admin, contact: contact, starts_at: 2.days.from_now)
      servico = instance_double(Crm::Meetings::CancelService)
      allow(servico).to receive(:perform).and_raise(Net::ReadTimeout)
      allow(Crm::Meetings::CancelService).to receive(:new).and_return(servico)

      call(admin, path, card_ids: [card.id], confirmation: 'EXCLUIR')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'crm.permanent_delete.meeting_cancel_failed', 'meeting_id' => meeting.id)
      expect(card.reload).to be_present
      expect(auditorias).to be_empty
    end
  end

  describe 'POST crm/pipelines/:id/permanent_delete' do
    let(:destino_and_stage) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
    let(:destino_stage) { create_crm_stage(account: account, pipeline: destino_and_stage.first, name: 'Proposta') }

    def path(funil = pipeline)
      "#{base}/crm/pipelines/#{funil.id}/permanent_delete"
    end

    before { destino_and_stage }

    it 'apaga o funil arquivado vazio com etapas, automações, caixas e visões, e solta as configurações' do
      automacao = account.crm_stage_automations.create!(pipeline: pipeline, stage: stage, name: 'Boas-vindas', trigger_event: :on_enter)
      Crm::PipelineInbox.create!(account: account, pipeline: pipeline, inbox: inbox, default_stage: stage)
      setting = Crm::InboxSetting.create!(account: account, inbox: inbox, default_pipeline: pipeline, default_stage: stage)
      Crm::SavedView.create!(account: account, user: admin, pipeline: pipeline, name: 'Minha', config: { 'filtro' => 'x' })
      create(:crm_ai_usage_event, account: account, pipeline_id: pipeline.id)
      pipeline.archived!

      call(admin, path, confirmation: 'Funil Comercial')

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to eq('status' => 'deleted', 'cards_count' => 0)
      restos = [Crm::Pipeline.exists?(pipeline.id), Crm::PipelineStage.exists?(stage.id), Crm::StageAutomation.exists?(automacao.id),
                Crm::PipelineInbox.exists?(pipeline_id: pipeline.id), Crm::SavedView.exists?(pipeline_id: pipeline.id)]
      expect(restos).to eq([false] * 5)
      expect([setting.reload.default_pipeline_id, setting.default_stage_id]).to eq([nil, nil])
      expect(Crm::AiUsageEvent.find_by!(account_id: account.id).pipeline_id).to be_nil
      expect(auditorias.sole.audited_changes).to eq('alvo' => 'funil', 'cards_apagados' => 0, 'card_ids' => [],
                                                    'pipeline_id' => pipeline.id, 'cards_movidos' => 0)
    end

    it 'recusa quem não é administrador (403)' do
      pipeline.archived!

      call(agent, path, confirmation: 'Funil Comercial')

      expect(response).to have_http_status(:forbidden)
      expect(pipeline.reload).to be_present
    end

    it 'recusa funil que não está arquivado (422)' do
      call(admin, path, confirmation: 'Funil Comercial')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('crm.permanent_delete.not_archived')
    end

    it 'recusa nome errado (422)' do
      pipeline.archived!

      call(admin, path, confirmation: 'Funil comercial')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('crm.permanent_delete.confirmation_mismatch')
      expect(pipeline.reload).to be_present
    end

    it 'não acha funil de outra conta (404)' do
      outra = create(:account)
      alheio = create_crm_pipeline(account: outra, user: create(:user, account: outra, role: :administrator)).first
      alheio.archived!

      call(admin, path(alheio), confirmation: 'Funil Comercial')

      expect(response).to have_http_status(:not_found)
      expect(alheio.reload).to be_present
    end

    it 'com cards, exige escolher mover ou apagar, e um destino válido' do
      card_arquivado(status: :open)
      pipeline.archived!
      outro_arquivado = create_crm_pipeline(account: account, user: admin, name: 'Velho')
      outro_arquivado.first.archived!

      call(admin, path, confirmation: 'Funil Comercial')
      expect(response.parsed_body).to eq('error' => 'crm.permanent_delete.pipeline_has_cards', 'cards_count' => 1)

      call(admin, path, confirmation: 'Funil Comercial', cards: 'jogar_fora')
      expect(response.parsed_body['error']).to eq('crm.permanent_delete.invalid_cards_mode')

      [stage, outro_arquivado.last, nil].each do |etapa|
        call(admin, path, confirmation: 'Funil Comercial', cards: 'move', target_stage_id: etapa&.id)
        expect(response.parsed_body['error']).to eq('crm.permanent_delete.invalid_target_stage')
      end
      expect(pipeline.reload).to be_present
    end

    it 'move os cards (o aberto para a etapa escolhida, o arquivado para a primeira) e apaga o funil' do
      aberto = card_arquivado(title: 'Aberto', status: :open)
      arquivado = card_arquivado(title: 'Arquivado')
      pipeline.archived!

      perform_enqueued_jobs(only: Crm::Pipelines::ExcluirDeVezJob) do
        call(admin, path, confirmation: 'Funil Comercial', cards: 'move', target_stage_id: destino_stage.id)
        expect(response).to have_http_status(:accepted)
        expect(response.parsed_body['payload']).to eq('status' => 'queued', 'cards_count' => 2)
      end

      expect(Crm::Pipeline.exists?(pipeline.id)).to be(false)
      expect(aberto.reload).to have_attributes(stage_id: destino_stage.id, status: 'open')
      expect(arquivado.reload).to have_attributes(stage_id: destino_and_stage.last.id, status: 'archived')
      expect(aberto.activities.where(event_type: 'move').count).to eq(1)
      expect(auditorias.sole.audited_changes).to include('alvo' => 'funil', 'card_ids' => [], 'cards_movidos' => 2)
    end

    it 'apaga os cards junto quando pedido' do
      card = create_card_cheio(account: account, user: admin, pipeline: pipeline, contact: contact, conversation: conversation)
      pipeline.archived!

      perform_enqueued_jobs(only: Crm::Pipelines::ExcluirDeVezJob) do
        call(admin, path, confirmation: 'Funil Comercial', cards: 'delete')
      end

      expect(response).to have_http_status(:accepted)
      expect(Crm::Pipeline.exists?(pipeline.id)).to be(false)
      expect(onde_o_card_ainda_aparece(card.id)).to eq([])
      expect(conversation.reload).to be_present
      expect(auditorias.sole.audited_changes).to include('alvo' => 'funil', 'cards_apagados' => 1, 'card_ids' => [card.id])
    end

    it 'não apaga quando o funil foi restaurado antes de o job rodar' do
      card_arquivado
      pipeline.archived!
      call(admin, path, confirmation: 'Funil Comercial', cards: 'delete')
      pipeline.active!

      perform_enqueued_jobs(only: Crm::Pipelines::ExcluirDeVezJob)

      expect(pipeline.reload.cards.count).to eq(1)
    end
  end

  describe 'DELETE contacts/:id com delete_crm_cards (LGPD)' do
    def destroy_contact(user, params = {})
      delete "#{base}/contacts/#{contact.id}", params: params, headers: user.create_new_auth_token, as: :json
    end

    it 'apaga o contato e, com o parâmetro, os cards dele de vez' do
      aberto = card_arquivado(status: :open)
      arquivado = card_arquivado(title: 'Antigo')

      destroy_contact(admin, delete_crm_cards: true)

      expect(response).to have_http_status(:ok)
      expect(Contact.exists?(contact.id)).to be(false)
      expect(Crm::Card.where(id: [aberto.id, arquivado.id])).to be_empty
      expect(auditorias.sole.audited_changes).to eq('alvo' => 'contato', 'cards_apagados' => 2,
                                                    'card_ids' => [aberto.id, arquivado.id].sort, 'contact_id' => contact.id)
    end

    it 'sem o parâmetro, mantém o comportamento de hoje: os cards ficam sem contato' do
      card = card_arquivado(status: :open)

      destroy_contact(admin)

      expect(response).to have_http_status(:ok)
      expect(card.reload.contact_id).to be_nil
      expect(auditorias).to be_empty
    end

    it 'não apaga o contato quando a reunião futura de um card não cancela' do
      card = card_arquivado(status: :open)
      create_reuniao(account: account, card: card, user: admin, contact: contact, starts_at: 2.days.from_now)
      servico = instance_double(Crm::Meetings::CancelService)
      allow(servico).to receive(:perform).and_raise(Errno::ECONNREFUSED)
      allow(Crm::Meetings::CancelService).to receive(:new).and_return(servico)

      destroy_contact(admin, delete_crm_cards: true)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('crm.permanent_delete.meeting_cancel_failed')
      expect([Contact.exists?(contact.id), Crm::Card.exists?(card.id)]).to eq([true, true])
    end
  end
end

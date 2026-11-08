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

    # Duas reuniões: a primeira cancela, a segunda não. Nada é apagado, e a resposta diz qual já foi cancelada (o cliente
    # já recebeu o aviso; o card tem a atividade).
    it 'quando a segunda reunião não cancela, diz qual já foi cancelada e não apaga nada' do
      card = card_arquivado
      primeira = create_reuniao(account: account, card: card, user: admin, contact: contact, starts_at: 2.days.from_now)
      segunda = create_reuniao(account: account, card: card, user: admin, contact: contact, starts_at: 3.days.from_now)
      allow(Crm::Meetings::CancelService).to receive(:new).and_wrap_original do |original, **args|
        raise Net::ReadTimeout if args[:meeting].id == segunda.id

        original.call(**args)
      end

      call(admin, path, card_ids: [card.id], confirmation: 'EXCLUIR')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'crm.permanent_delete.meeting_cancel_failed', 'meeting_id' => segunda.id,
                                         'canceled_meeting_ids' => [primeira.id])
      expect([card.reload.status, primeira.reload.status, segunda.reload.status]).to eq(%w[archived canceled scheduled])
      expect(card.activities.where(event_type: 'meeting_canceled').count).to eq(1)
      expect(auditorias).to be_empty
    end

    # O card voltou ao quadro entre a conferência do controller e a transação (o calendário leva segundos).
    it 'não apaga o card restaurado no meio do caminho (422), e devolve as reuniões já canceladas' do
      card = card_arquivado
      futura = create_reuniao(account: account, card: card, user: admin, contact: contact, starts_at: 2.days.from_now)
      allow(Crm::Meetings::CancelService).to receive(:new).and_wrap_original do |original, **args|
        original.call(**args).tap { Crm::Card.find(card.id).update!(status: :open) }
      end

      call(admin, path, card_ids: [card.id], confirmation: 'EXCLUIR')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'crm.permanent_delete.not_archived', 'canceled_meeting_ids' => [futura.id])
      expect(card.reload).to be_open
      expect(auditorias).to be_empty
    end

    it 'não apaga nada quando a reunião futura não cancela no calendário (422)' do
      card = card_arquivado
      meeting = create_reuniao(account: account, card: card, user: admin, contact: contact, starts_at: 2.days.from_now)
      servico = instance_double(Crm::Meetings::CancelService)
      allow(servico).to receive(:perform).and_raise(Net::ReadTimeout)
      allow(Crm::Meetings::CancelService).to receive(:new).and_return(servico)

      call(admin, path, card_ids: [card.id], confirmation: 'EXCLUIR')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'crm.permanent_delete.meeting_cancel_failed', 'meeting_id' => meeting.id,
                                         'canceled_meeting_ids' => [])
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

    def mover_para(etapa)
      perform_enqueued_jobs(only: Crm::Pipelines::ExcluirDeVezJob) do
        call(admin, path, confirmation: 'Funil Comercial', cards: 'move', target_stage_id: etapa.id)
      end
      expect(response).to have_http_status(:accepted)
    end

    # #1498: o atendimento Resolvido que vai para um funil de Vender volta aberto, e por isso entra na etapa escolhida,
    # no quadro; nunca aberto na primeira etapa.
    it 'card Resolvido de Atender que vai para Vender entra aberto na etapa escolhida' do
      pipeline.update!(counts_as_sale: false)
      resolvido = card_arquivado(title: 'Resolvido', status: :resolved)
      pipeline.archived!

      mover_para(destino_stage)

      expect(resolvido.reload).to have_attributes(pipeline_id: destino_and_stage.first.id, stage_id: destino_stage.id, status: 'open')
    end

    it 'card Ganho de Vender que vai para Atender fica Resolvido, na primeira etapa, fora do quadro' do
      destino_and_stage.first.update!(counts_as_sale: false)
      ganho = card_arquivado(title: 'Ganho', status: :won, value_cents: 10_000)
      pipeline.archived!

      mover_para(destino_stage)

      expect(ganho.reload).to have_attributes(stage_id: destino_and_stage.last.id, status: 'resolved')
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
      falha = Audited.audit_class.find_by!(auditable: account, action: Crm::ExclusaoDefinitiva::FALHOU)
      expect(falha.audited_changes).to eq('alvo' => 'funil', 'motivo' => 'not_archived', 'pipeline_id' => pipeline.id)
      expect(auditorias).to be_empty
    end
  end

  describe 'POST crm/contacts/:contact_id/permanent_delete (LGPD)' do
    let(:path) { "#{base}/crm/contacts/#{contact.id}/permanent_delete" }

    # A rota só existe com a flag (#2143: o servidor confere).
    before { account.enable_features!(:crm_arquivados) }

    it 'apaga o contato e os cards dele de vez, abertos, ganhos e arquivados, e deixa a conversa' do
      aberto = card_arquivado(status: :open)
      ganho = card_arquivado(title: 'Venda', status: :won, value_cents: 90_000)
      arquivado = card_arquivado(title: 'Antigo')
      conversation

      call(admin, path, confirmation: 'EXCLUIR', cards: 'delete')

      expect(response).to have_http_status(:ok)
      ids = [aberto.id, ganho.id, arquivado.id].sort
      expect(response.parsed_body['payload']).to eq('deleted_card_ids' => ids, 'anonymized_card_ids' => [], 'mode' => 'delete')
      expect(Contact.exists?(contact.id)).to be(false)
      expect(Crm::Card.where(id: ids)).to be_empty
      expect(Conversation.exists?(conversation.id)).to be(true)
      expect(auditorias.sole.audited_changes).to eq('alvo' => 'contato', 'cards_apagados' => 3, 'card_ids' => ids,
                                                    'contact_id' => contact.id, 'modo' => 'delete')
    end

    it 'exige a confirmação digitada (422) e não apaga nada' do
      card = card_arquivado(status: :open)

      ['', 'excluir', 'true'].each do |confirmation|
        call(admin, path, confirmation: confirmation, cards: 'delete')

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('crm.permanent_delete.confirmation_mismatch')
      end
      expect([Contact.exists?(contact.id), Crm::Card.exists?(card.id)]).to eq([true, true])
    end

    it 'recusa agente sem função (403) e não apaga nada' do
      card = card_arquivado(status: :won)

      call(agent, path, confirmation: 'EXCLUIR', cards: 'delete')

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq('crm.permanent_delete.admin_only')
      expect([Contact.exists?(contact.id), Crm::Card.exists?(card.id)]).to eq([true, true])
    end

    it 'não acha contato de outra conta (404)' do
      outra = create(:account)
      alheio = outra.contacts.create!(name: 'Alheio', phone_number: '+5511999990009')

      call(admin, "#{base}/crm/contacts/#{alheio.id}/permanent_delete", confirmation: 'EXCLUIR')

      expect(response).to have_http_status(:not_found)
      expect(Contact.exists?(alheio.id)).to be(true)
    end

    # Com a flag crm_arquivados (sem ela, como na main: ver excluir_contato_calendario_e_flag_spec).
    it 'o DELETE do contato de sempre mantém os cards sem dado pessoal, e o parâmetro antigo não apaga card' do
      account.enable_features!(:crm_arquivados)
      card = card_arquivado(status: :open, description: 'detalhe')

      delete "#{base}/contacts/#{contact.id}", params: { delete_crm_cards: true }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(card.reload.attributes.slice('contact_id', 'title', 'description'))
        .to eq('contact_id' => nil, 'title' => "Removed customer ##{card.id}", 'description' => nil)
      expect(auditorias.sole.audited_changes).to include('modo' => 'keep', 'cards_apagados' => 0, 'cards_mantidos' => 1)
    end

    it 'não apaga o contato quando a reunião futura de um card não cancela' do
      card = card_arquivado(status: :open)
      create_reuniao(account: account, card: card, user: admin, contact: contact, starts_at: 2.days.from_now)
      servico = instance_double(Crm::Meetings::CancelService)
      allow(servico).to receive(:perform).and_raise(Errno::ECONNREFUSED)
      allow(Crm::Meetings::CancelService).to receive(:new).and_return(servico)

      call(admin, path, confirmation: 'EXCLUIR', cards: 'delete')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'crm.permanent_delete.meeting_cancel_failed', 'canceled_meeting_ids' => [])
      expect([Contact.exists?(contact.id), Crm::Card.exists?(card.id)]).to eq([true, true])
    end
  end
end

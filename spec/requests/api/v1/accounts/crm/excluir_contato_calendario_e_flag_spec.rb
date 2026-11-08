require 'rails_helper'

# #2096: excluir o contato com reunião do Google cujo calendário não se alcança mais, nos três caminhos (DELETE de
# sempre, lote e a rota nova), e o mesmo contato sem a flag crm_arquivados, que fica como na main.
RSpec.describe 'CRM excluir contato: calendário fora de alcance e flag', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:contact) { account.contacts.create!(name: 'Cliente', phone_number: '+5511999990051') }
  let(:card) do
    pipeline, stage = pipeline_and_stage
    account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: 'Pedido', status: :open)
  end
  let(:base) { "/api/v1/accounts/#{account.id}" }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true') { example.run }
  end

  # Reunião do Google já marcada no calendário (o id do evento), gravada como a agenda grava. `inbox: nil` é a caixa
  # removida (inbox_id nulo): a reunião não passa mais na validação.
  def reuniao_google(inbox:)
    account.crm_meetings.new(card: card, inbox: inbox, created_by: admin, title: 'Visita', provider: :google, status: :scheduled,
                             external_event_id: "evt-#{SecureRandom.hex(4)}", timezone: 'America/Sao_Paulo',
                             starts_at: 2.days.from_now, ends_at: 2.days.from_now + 30.minutes).tap { |m| m.save!(validate: false) }
  end

  def caixa_de_email(calendar_enabled:)
    create(:channel_email, account: account, calendar_enabled: calendar_enabled).inbox
  end

  def auditorias
    Audited.audit_class.where(auditable: account, action: Crm::ExclusaoDefinitiva::ACAO)
  end

  def o_google_nao_e_chamado
    allow(Google::CalendarEventService).to receive(:new).and_call_original
    yield
    expect(Google::CalendarEventService).not_to have_received(:new)
  end

  context 'with the crm_arquivados flag' do
    before { account.enable_features!(:crm_arquivados) }

    it 'DELETE contacts/:id: reunião sem caixa é cancelada só aqui, sem 500 nem 422' do
      reuniao = reuniao_google(inbox: nil)

      o_google_nao_e_chamado { delete "#{base}/contacts/#{contact.id}", headers: admin.create_new_auth_token, as: :json }

      expect(response).to have_http_status(:ok)
      expect([Contact.exists?(contact.id), reuniao.reload.status, card.reload.title])
        .to eq([false, 'canceled', "Removed customer ##{card.id}"])
      expect(auditorias.sole.audited_changes)
        .to include('reunioes_canceladas' => 1, 'reunioes_so_aqui' => 1, 'canceled_meeting_ids' => [reuniao.id])
    end

    it 'lote: reunião sem caixa é cancelada só aqui e o contato sai' do
      reuniao = reuniao_google(inbox: nil)

      o_google_nao_e_chamado { Contacts::BulkDeleteService.new(account: account, contact_ids: [contact.id], user: admin).perform }

      expect([Contact.exists?(contact.id), reuniao.reload.status]).to eq([false, 'canceled'])
      expect(auditorias.sole.user).to eq(admin)
    end

    it 'rota nova, keep e delete: reunião sem caixa é cancelada só aqui', :aggregate_failures do
      reuniao = reuniao_google(inbox: nil)
      path = "#{base}/crm/contacts/#{contact.id}/permanent_delete"

      o_google_nao_e_chamado { post path, params: { confirmation: 'EXCLUIR', cards: 'keep' }, headers: admin.create_new_auth_token, as: :json }

      expect(response).to have_http_status(:ok)
      expect(reuniao.reload.status).to eq('canceled')

      outro = account.contacts.create!(name: 'Outro', phone_number: '+5511999990052')
      card.update!(contact: outro)
      reuniao_do_outro = reuniao_google(inbox: nil)
      post "#{base}/crm/contacts/#{outro.id}/permanent_delete", params: { confirmation: 'EXCLUIR', cards: 'delete' },
                                                                headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect([Contact.exists?(outro.id), Crm::Card.exists?(card.id), Crm::Meeting.exists?(reuniao_do_outro.id)]).to eq([false, false, false])
    end

    # Dono do card que saiu da conta (comum): o card e o lembrete da reunião não passam mais na validação. O cancelamento
    # não pode depender deles, ou o Google apaga o evento e a reunião volta a "marcada".
    context 'when the card owner left the account' do
      let(:quem_saiu) { create(:user) }

      before { card.update_columns(owner_id: quem_saiu.id) } # rubocop:disable Rails/SkipsModelValidations

      def com_lembrete(reuniao)
        Crm::FollowUp.new(account: account, card: card, created_by: quem_saiu, title: 'Lembrete', due_at: 1.day.from_now,
                          timezone: 'America/Sao_Paulo', status: :pending).tap { |lembrete| lembrete.save!(validate: false) }
                     .tap { |lembrete| reuniao.update_columns(reminder_id: lembrete.id) } # rubocop:disable Rails/SkipsModelValidations
      end

      it 'DELETE, lote e rota nova cancelam e excluem', :aggregate_failures do
        reuniao = reuniao_google(inbox: nil)
        lembrete = com_lembrete(reuniao)
        delete "#{base}/contacts/#{contact.id}", headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:ok)
        expect([reuniao.reload.status, lembrete.reload.status, Contact.exists?(contact.id)]).to eq(['canceled', 'canceled', false])

        segundo = account.contacts.create!(name: 'Segundo', phone_number: '+5511999990053')
        card.update_columns(contact_id: segundo.id) # rubocop:disable Rails/SkipsModelValidations
        reuniao = reuniao_google(inbox: nil)
        Contacts::BulkDeleteService.new(account: account, contact_ids: [segundo.id], user: admin).perform
        expect([reuniao.reload.status, Contact.exists?(segundo.id)]).to eq(['canceled', false])

        terceiro = account.contacts.create!(name: 'Terceiro', phone_number: '+5511999990054')
        card.update_columns(contact_id: terceiro.id) # rubocop:disable Rails/SkipsModelValidations
        reuniao = reuniao_google(inbox: nil)
        post "#{base}/crm/contacts/#{terceiro.id}/permanent_delete",
             params: { confirmation: 'EXCLUIR', cards: 'keep' }, headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:ok)
        expect([reuniao.reload.status, Contact.exists?(terceiro.id)]).to eq(['canceled', false])
      end
    end

    it 'calendário desligado na caixa: cancela só aqui' do
      reuniao = reuniao_google(inbox: caixa_de_email(calendar_enabled: false))

      o_google_nao_e_chamado { delete "#{base}/contacts/#{contact.id}", headers: admin.create_new_auth_token, as: :json }

      expect(response).to have_http_status(:ok)
      expect(reuniao.reload.status).to eq('canceled')
    end

    it 'token que não renova (RuntimeError do refresh): 422 meeting_cancel_failed, nada sai' do
      reuniao = reuniao_google(inbox: caixa_de_email(calendar_enabled: true))
      servico = instance_double(Google::CalendarEventService)
      allow(servico).to receive(:delete_event).and_raise(RuntimeError, 'A refresh_token is not available')
      allow(Google::CalendarEventService).to receive(:new).and_return(servico)
      allow(Crm::Config).to receive(:calendar_google_simulate?).and_return(false)

      delete "#{base}/contacts/#{contact.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'crm.permanent_delete.meeting_cancel_failed', 'meeting_id' => reuniao.id)
      expect([Contact.exists?(contact.id), reuniao.reload.status, card.reload.title]).to eq([true, 'scheduled', 'Pedido'])
      expect(auditorias).to be_empty
    end
  end

  context 'without the crm_arquivados flag' do
    it 'DELETE contacts/:id: como na main, solta o card com o título e não toca a reunião nem a Auditoria' do
      reuniao = create_reuniao(account: account, card: card, user: admin, contact: contact, starts_at: 2.days.from_now)
      allow(Crm::Meetings::CancelarFuturas).to receive(:new).and_call_original

      delete "#{base}/contacts/#{contact.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect([Contact.exists?(contact.id), card.reload.contact_id, card.title, reuniao.reload.status])
        .to eq([false, nil, 'Pedido', 'scheduled'])
      expect(card.metadata).not_to have_key(Crm::Cards::Anonimizador::MARCA)
      expect(Crm::Meetings::CancelarFuturas).not_to have_received(:new)
      expect(auditorias).to be_empty
    end

    it 'lote: como na main' do
      reuniao = create_reuniao(account: account, card: card, user: admin, contact: contact, starts_at: 2.days.from_now)

      Contacts::BulkDeleteService.new(account: account, contact_ids: [contact.id], user: admin).perform

      expect([Contact.exists?(contact.id), card.reload.contact_id, card.title, reuniao.reload.status])
        .to eq([false, nil, 'Pedido', 'scheduled'])
      expect(auditorias).to be_empty
    end
  end
end

require 'rails_helper'

# LGPD (#2096, decisões 1 e 10): excluir o contato pergunta o que fazer com os cards, sem padrão; "manter" deixa os
# cards sem dado pessoal. As prévias alimentam as janelas da Parte B. Só administrador.
RSpec.describe 'CRM excluir contato com escolha dos cards e prévias', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:contact) { account.contacts.create!(name: 'Cliente', phone_number: '+5511999990041') }
  let(:base) { "/api/v1/accounts/#{account.id}" }
  let(:path) { "#{base}/crm/contacts/#{contact.id}/permanent_delete" }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true') { example.run }
  end

  before { account.enable_features!(:crm_arquivados) }

  def card(status: :open, **attrs)
    account.crm_cards.create!({ pipeline: pipeline, stage: stage, contact: contact, title: 'Pedido', status: status }.merge(attrs))
  end

  # O desfecho guardado do arquivado (Parte A, #2094) sem passar pelos callbacks do card.
  def ganho_arquivado(**attrs)
    card(status: :archived, **attrs).tap { |c| c.update_columns(metadata: { 'desfecho_arquivado' => 'won' }) } # rubocop:disable Rails/SkipsModelValidations
  end

  def call(user, params = {})
    post path, params: params, headers: user.create_new_auth_token, as: :json
  end

  def auditorias
    Audited.audit_class.where(auditable: account, action: Crm::ExclusaoDefinitiva::ACAO)
  end

  def falhar_o_calendario
    servico = instance_double(Crm::Meetings::CancelService)
    allow(servico).to receive(:perform).and_raise(Net::ReadTimeout)
    allow(Crm::Meetings::CancelService).to receive(:new).and_return(servico)
  end

  describe 'POST crm/contacts/:contact_id/permanent_delete' do
    it 'exige a escolha quando o contato tem cards, e não apaga nada por omissão' do
      aberto = card

      call(admin, confirmation: 'EXCLUIR')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'crm.permanent_delete.contact_cards_choice_required', 'cards_count' => 1)
      expect([Contact.exists?(contact.id), aberto.reload.title]).to eq([true, 'Pedido'])
    end

    it 'recusa escolha desconhecida' do
      card

      call(admin, confirmation: 'EXCLUIR', cards: 'nullify')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('crm.permanent_delete.invalid_cards_mode')
      expect(Contact.exists?(contact.id)).to be(true)
    end

    it 'contato sem card sai sem escolha' do
      call(admin, confirmation: 'EXCLUIR')

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to eq('deleted_card_ids' => [], 'anonymized_card_ids' => [], 'mode' => 'delete')
      expect(Contact.exists?(contact.id)).to be(false)
    end

    it 'keep: mantém os cards sem dado pessoal, cancela a reunião futura e audita só ids' do
      ganho = card(status: :won, value_cents: 90_000, description: 'detalhe', custom_attributes: { 'cpf' => '000' })
      arquivado = card(status: :archived)
      reuniao = create_reuniao(account: account, card: ganho, user: admin, contact: contact, starts_at: 2.days.from_now)

      call(admin, confirmation: 'EXCLUIR', cards: 'keep')

      expect(response).to have_http_status(:ok)
      ids = [ganho.id, arquivado.id]
      expect(response.parsed_body['payload']).to eq('deleted_card_ids' => [], 'anonymized_card_ids' => ids, 'mode' => 'keep')
      expect(Contact.exists?(contact.id)).to be(false)
      expect(ganho.reload.attributes.slice('title', 'status', 'value_cents', 'description', 'custom_attributes', 'contact_id'))
        .to eq('title' => "Removed customer ##{ganho.id}", 'status' => 'won', 'value_cents' => 90_000, 'description' => nil,
               'custom_attributes' => {}, 'contact_id' => nil)
      expect(reuniao.reload).to be_canceled
      expect(auditorias.sole.audited_changes)
        .to eq('alvo' => 'contato', 'cards_apagados' => 0, 'card_ids' => [], 'contact_id' => contact.id, 'modo' => 'keep',
               'cards_mantidos' => 2, 'card_ids_mantidos' => ids, 'reunioes_canceladas' => 1,
               'reunioes_so_aqui' => 0)
    end

    it 'keep: não exclui nem limpa nada quando a reunião futura não cancela no calendário (422)' do
      aberto = card
      reuniao = create_reuniao(account: account, card: aberto, user: admin, contact: contact, starts_at: 2.days.from_now)
      falhar_o_calendario

      call(admin, confirmation: 'EXCLUIR', cards: 'keep')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'crm.permanent_delete.meeting_cancel_failed', 'meeting_id' => reuniao.id,
                                         'canceled_meeting_ids' => [])
      expect([Contact.exists?(contact.id), aberto.reload.title, reuniao.reload.status]).to eq([true, 'Pedido', 'scheduled'])
      expect(auditorias).to be_empty
    end

    # #2143: o servidor confere a flag, e não só a tela.
    it 'sem a flag crm_arquivados a rota não existe (404) e nada sai' do
      account.disable_features!(:crm_arquivados)
      card

      call(admin, confirmation: 'EXCLUIR', cards: 'delete')
      expect(response).to have_http_status(:not_found)
      get "#{path}_preview", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      expect(Contact.exists?(contact.id)).to be(true)
      expect(auditorias).to be_empty
    end

    # #2143: impasse com a conversão de um lead que se repetiu nas retentativas.
    it 'impasse no banco responde 409 contact_busy, e não 500' do
      allow(Crm::ExclusaoDefinitiva).to receive(:contato!).and_raise(ActiveRecord::Deadlocked)

      call(admin, confirmation: 'EXCLUIR')

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['error']).to eq('contact_busy')
    end

    it 'recusa agente (403) nos dois modos' do
      aberto = card

      %w[keep delete].each do |modo|
        call(agent, confirmation: 'EXCLUIR', cards: modo)

        expect(response).to have_http_status(:forbidden)
      end
      expect([Contact.exists?(contact.id), aberto.reload.title]).to eq([true, 'Pedido'])
    end
  end

  describe 'DELETE contacts/:id' do
    # #2143: impasse com a conversão de um lead do mesmo contato; nada sai e a pessoa tenta de novo.
    it 'impasse no banco responde 409 contact_busy e o contato fica' do
      allow(Autonomia::Prospecting::LeadsDoContatoExcluido).to receive(:new).and_raise(ActiveRecord::Deadlocked)

      delete "#{base}/contacts/#{contact.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['error']).to eq('contact_busy')
      expect(Contact.exists?(contact.id)).to be(true)
    end

    it 'não exclui o contato quando a reunião futura de um card não cancela no calendário (422)' do
      aberto = card
      reuniao = create_reuniao(account: account, card: aberto, user: admin, contact: contact, starts_at: 2.days.from_now)
      falhar_o_calendario

      delete "#{base}/contacts/#{contact.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'crm.permanent_delete.meeting_cancel_failed', 'meeting_id' => reuniao.id)
      expect([Contact.exists?(contact.id), aberto.reload.title]).to eq([true, 'Pedido'])
    end

    it 'cancela a reunião futura e mantém o card sem dado pessoal' do
      aberto = card
      reuniao = create_reuniao(account: account, card: aberto, user: admin, contact: contact, starts_at: 2.days.from_now)

      delete "#{base}/contacts/#{contact.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect([reuniao.reload.status, aberto.reload.title]).to eq(['canceled', "Removed customer ##{aberto.id}"])
    end
  end

  describe 'GET crm/contacts/:contact_id/permanent_delete_preview' do
    let(:preview_path) { "#{base}/crm/contacts/#{contact.id}/permanent_delete_preview" }

    it 'lista os cards com funil, etapa, valor, desfecho e a reunião futura, sem título nem dado do cliente' do
      arquivado = ganho_arquivado(value_cents: 5_000)
      aberto = card
      reuniao = create_reuniao(account: account, card: aberto, user: admin, contact: contact, starts_at: 2.days.from_now)

      get preview_path, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      payload = response.parsed_body['payload']
      expect(payload.slice('contact_id', 'cards_count')).to eq('contact_id' => contact.id, 'cards_count' => 2)
      expect(payload['timezone']).to eq(Crm::Timezone::Resolver.new(account: account).zone_or_default.tzinfo.name)
      funil = { 'id' => pipeline.id, 'name' => pipeline.name, 'status' => 'active', 'counts_as_sale' => pipeline.counts_as_sale }
      expect(payload['cards'].first).to eq('id' => arquivado.id, 'pipeline' => funil, 'stage_name' => stage.name, 'value_cents' => 5_000,
                                           'currency' => 'BRL', 'status' => 'archived', 'desfecho' => 'won', 'upcoming_meeting' => nil)
      expect(payload['cards'].last['upcoming_meeting'])
        .to eq('starts_at' => reuniao.starts_at.as_json, 'provider' => 'internal')
      expect(payload.to_json).not_to include('Pedido', contact.phone_number)
    end

    it 'recusa agente (403)' do
      get preview_path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET crm/pipelines/:id/permanent_delete_preview' do
    let(:preview_path) { "#{base}/crm/pipelines/#{pipeline.id}/permanent_delete_preview" }

    it 'conta os cards, as vendas (inclusive o arquivado que era ganho) e lista as reuniões futuras' do
      card(status: :open, value_cents: 1_000)
      card(status: :won, value_cents: 20_000)
      ganho_arquivado(value_cents: 30_000)
      card(status: :archived, value_cents: 70_000)
      perdido = card(status: :lost, value_cents: 40_000)
      reuniao = create_reuniao(account: account, card: perdido, user: admin, contact: contact, starts_at: 2.days.from_now)
      pipeline.archived!

      get preview_path, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to eq(
        'pipeline_id' => pipeline.id, 'cards_count' => 5, 'open_cards_count' => 1, 'closed_or_archived_count' => 4,
        'won_value_cents' => 50_000, 'currency' => 'BRL', 'won_values' => [{ 'currency' => 'BRL', 'value_cents' => 50_000 }],
        'upcoming_meetings_count' => 1,
        'upcoming_meetings' => [{ 'card_id' => perdido.id, 'starts_at' => reuniao.starts_at.as_json, 'provider' => 'internal' }],
        'timezone' => Crm::Timezone::Resolver.new(account: account).zone_or_default.tzinfo.name
      )
    end

    it 'não soma vendas em funil que não conta como venda, e não soma moedas diferentes' do
      card(status: :won, value_cents: 20_000)
      card(status: :won, value_cents: 5_000, currency: 'USD')

      get preview_path, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['payload'].slice('won_value_cents', 'currency', 'won_values'))
        .to eq('won_value_cents' => nil, 'currency' => nil,
               'won_values' => [{ 'currency' => 'BRL', 'value_cents' => 20_000 }, { 'currency' => 'USD', 'value_cents' => 5_000 }])

      pipeline.update!(counts_as_sale: false)
      get preview_path, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['payload'].slice('won_value_cents', 'won_values')).to eq('won_value_cents' => nil, 'won_values' => [])
    end

    it 'recusa agente (403)' do
      get preview_path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end

require 'rails_helper'

# #2296: o "Ver" de Números › "De onde vieram os clientes" abre a Lista com `entrou_em` + `anuncio=<id do anúncio>`. Para a
# função personalizada sem `meta_ads_view`, o parâmetro é ignorado: filtrar por ele revelaria qual card veio de qual
# anúncio (quem tem um id descobriria os cards dele). Administrador e função com a chave filtram.
RSpec.describe 'Filtro por anúncio da Lista com meta_ads_view (#2296)', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      travel_to(Time.utc(2026, 10, 20, 15, 0)) { example.run }
    end
  end

  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:sem_chave) { pessoa_com(base) }
  let(:com_view) { pessoa_com(base + %w[meta_ads_view]) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:inbox) { create_crm_inbox(account: account, members: [sem_chave, com_view]) }
  let(:anuncio) { '120210000000101' }
  let!(:do_anuncio) { card('Veio do anúncio', 'source' => 'meta_ctwa', 'source_id' => anuncio) }
  let!(:direto) { card('Chegou direto') }

  def base = %w[crm_view crm_manage_cards contact_view conversation_manage]

  def pessoa_com(permissions)
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    user
  end

  def card(titulo, campaign = nil)
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: create(:contact, account: account))
    conversation.update_columns(additional_attributes: { 'campaign' => campaign }) if campaign # rubocop:disable Rails/SkipsModelValidations
    account.crm_cards.create!(pipeline: pipeline_and_stage.first, stage: pipeline_and_stage.last, primary_conversation: conversation,
                              inbox: inbox, title: titulo, created_at: Time.utc(2026, 10, 5, 12))
  end

  def ids(user, **params)
    get "/api/v1/accounts/#{account.id}/crm/cards",
        params: { pipeline_id: pipeline_and_stage.first.id, entrou_em: '2026-10', **params }, headers: auth_headers(user)
    expect(response).to have_http_status(:ok)
    response.parsed_body['payload'].pluck('id')
  end

  it 'sem meta_ads_view: o parâmetro anuncio é ignorado, e a lista é a do mês inteiro' do
    expect(ids(sem_chave, anuncio: anuncio)).to contain_exactly(do_anuncio.id, direto.id)
    expect(ids(sem_chave, anuncio: '999999')).to contain_exactly(do_anuncio.id, direto.id)
  end

  it 'sem meta_ads_view e sem o mês: o anuncio sozinho também é ignorado, como se não viesse' do
    get "/api/v1/accounts/#{account.id}/crm/cards",
        params: { pipeline_id: pipeline_and_stage.first.id, anuncio: anuncio }, headers: auth_headers(sem_chave)
    expect(response.parsed_body['payload'].pluck('id')).to contain_exactly(do_anuncio.id, direto.id)

    get "/api/v1/accounts/#{account.id}/crm/cards",
        params: { pipeline_id: pipeline_and_stage.first.id, anuncio: anuncio }, headers: auth_headers(admin)
    expect(response.parsed_body['payload']).to be_empty
  end

  it 'administrador e função com meta_ads_view filtram pelo anúncio' do
    [admin, com_view].each do |user|
      expect(ids(user, anuncio: anuncio)).to contain_exactly(do_anuncio.id)
      expect(ids(user, anuncio: '999999')).to be_empty
    end
  end
end

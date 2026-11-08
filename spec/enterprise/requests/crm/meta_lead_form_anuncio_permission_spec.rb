require 'rails_helper'

# #2558: o card de quem chegou pelo formulário do anúncio da Meta guarda o formulário, o anúncio e a campanha em
# metadata.meta_lead_form. A função personalizada sem `meta_ads_view` (nem `meta_ads_manage`) recebe dali só a hora da
# captura (e as respostas, pela regra do contato inteiro), como no resto do anúncio de origem (#2271). Lista, detalhe e
# tempo real passam pelo mesmo Crm::Cards::PayloadBuilder.
RSpec.describe 'Formulário do anúncio da Meta no card com meta_ads_view (#2558)', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:sem_chave) { pessoa_com(base) }
  let(:com_view) { pessoa_com(base + %w[meta_ads_view]) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:inbox) { create_crm_inbox(account: account, members: [sem_chave, com_view]) }
  let(:contato) { account.contacts.create!(name: 'Cliente Teste', phone_number: '+5511900001111') }
  let(:conversa) { create_crm_conversation(account: account, inbox: inbox, contact: contato) }
  let(:origem) do
    { 'leadgen_id' => '990001', 'form_id' => '880001', 'form_name' => 'Formulário Primavera', 'ad_id' => '120200000000000001',
      'ad_name' => 'Anúncio Carrossel', 'campaign_name' => 'Campanha Primavera', 'captured_at' => '2026-11-01T12:00:00Z',
      'fields' => [{ 'key' => 'city', 'value' => 'Campinas' }] }
  end
  let(:identificadores) { ['880001', '120200000000000001', 'Formulário Primavera', 'Anúncio Carrossel', 'Campanha Primavera'] }
  let!(:card) do
    account.crm_cards.create!(pipeline: pipeline_and_stage.first, stage: pipeline_and_stage.last, inbox: inbox, contact: contato,
                              owner: admin, primary_conversation: conversa, title: 'Lead do formulário',
                              metadata: { 'meta_lead_form' => origem })
  end

  def base = %w[crm_view crm_manage_cards contact_view conversation_manage]
  def crm = "/api/v1/accounts/#{account.id}/crm"

  def pessoa_com(permissions)
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    user
  end

  def formulario(superficie, user)
    path = superficie == :detalhe ? "cards/#{card.id}" : 'cards'
    get "#{crm}/#{path}", params: { pipeline_id: card.pipeline_id }, headers: auth_headers(user)
    expect(response).to have_http_status(:ok)
    payload = response.parsed_body['payload']
    linha = superficie == :detalhe ? payload : payload.find { |item| item['id'] == card.id }
    linha.dig('metadata', 'meta_lead_form')
  end

  it 'sem meta_ads_view: só a hora da captura, sem formulário, anúncio nem campanha, no detalhe e na lista' do
    %i[detalhe cards].each do |superficie|
      lido = formulario(superficie, sem_chave)

      expect(lido).to include('captured_at' => '2026-11-01T12:00:00Z')
      expect(lido.keys).not_to include('form_id', 'form_name', 'ad_id', 'ad_name', 'campaign_name', 'leadgen_id')
      identificadores.each { |texto| expect(response.body).not_to include(texto) }
    end
  end

  it 'com meta_ads_view e o administrador: o formulário, o anúncio e a campanha' do
    [com_view, admin].each do |user|
      expect(formulario(:detalhe, user)).to include('form_name' => 'Formulário Primavera', 'ad_name' => 'Anúncio Carrossel',
                                                    'ad_id' => '120200000000000001', 'campaign_name' => 'Campanha Primavera')
    end
  end

  it 'tempo real: cada destinatário recebe o formulário que a chave dele permite' do
    enviados = {}
    allow(ActionCableBroadcastJob).to receive(:perform_later) do |tokens, _evento, dados|
      enviados[tokens.first] = dados[:metadata]['meta_lead_form']
    end

    Crm::Cards::Broadcaster.broadcast(card, Events::Types::CRM_CARD_UPDATED)

    expect(enviados.fetch(sem_chave.pubsub_token).keys).not_to include('form_name', 'ad_name', 'ad_id', 'campaign_name', 'form_id')
    expect(enviados.fetch(sem_chave.pubsub_token).to_json).not_to include(*identificadores)
    [com_view, admin].each do |user|
      expect(enviados.fetch(user.pubsub_token)).to include('ad_name' => 'Anúncio Carrossel', 'form_name' => 'Formulário Primavera')
    end
  end
end

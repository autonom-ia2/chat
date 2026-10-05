require 'rails_helper'

# Ponte anúncio → landing page → WhatsApp (#1011), ponta a ponta pelo caminho real:
# aviso público da página (POST /l/:code/clicks) → mensagem do WhatsApp Cloud com #TOKEN →
# card → telas do CRM. Critérios CA-2.2 (formulário vence o texto editado) e CA-2.3
# (campanha da página no filtro de campanha do CRM, uma opção por campanha).
RSpec.describe 'Ponte LP: campanha e formulário no CRM', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) do
    create(:channel_whatsapp, account: account, phone_number: '+15551234567', provider: 'whatsapp_cloud', validate_provider_config: false,
                              sync_templates: false)
  end
  let(:inbox) { channel.inbox }
  let(:origin) { 'https://placement.com.br' }
  let!(:tracked_link) do
    Ctwa::TrackedLink.create!(account: account, inbox: inbox, name: 'LP Seguro Viagem', code: 'ABC234', usage: 'website',
                              allowed_origins: [origin])
  end
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:api) { "/api/v1/accounts/#{account.id}" }
  let(:usa_fields) do
    [{ 'key' => 'destination', 'label' => 'Destino', 'value' => 'América do Norte - EUA' },
     { 'key' => 'ages', 'label' => 'Idades', 'value' => '72' }]
  end

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true') { example.run }
  end

  before { inbox.add_members([admin.id]) }

  after do
    Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) }
  end

  def campaign_params(utm_id, utm_campaign)
    { 'utm_source' => 'meta', 'utm_medium' => 'paid', 'utm_campaign' => utm_campaign, 'utm_id' => utm_id }
  end

  def page_signal(token:, params:, fields: usa_fields)
    body = { 'token' => token, 'page_url' => "#{origin}/seguro-viagem", 'consent' => true, 'params' => params,
             'lead' => { 'fields' => fields } }
    post "/l/#{tracked_link.code}/clicks", params: body.to_json,
                                           headers: { 'CONTENT_TYPE' => 'text/plain;charset=UTF-8', 'Origin' => origin }
    expect(response).to have_http_status(:no_content)
  end

  def whatsapp_message(wa_id:, text:)
    params = {
      phone_number: channel.phone_number,
      object: 'whatsapp_business_account',
      entry: [{ changes: [{ value: {
        contacts: [{ profile: { name: "Lead #{wa_id}" }, wa_id: wa_id }],
        messages: [{ from: wa_id, id: "wamid.#{SecureRandom.hex(6)}", timestamp: Time.current.to_i.to_s, type: 'text',
                     text: { body: text } }]
      } }] }]
    }.with_indifferent_access
    Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: params).perform
    inbox.contact_inboxes.find_by!(source_id: wa_id).conversations.sole
  end

  def card_for(conversation)
    pipeline, stage = pipeline_and_stage
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: "Lead #{conversation.display_id}",
                              primary_conversation: conversation, contact: conversation.contact, inbox: inbox)
  end

  def get_ok(path, params = {})
    get "#{api}#{path}", params: params, headers: auth_headers(admin)
    expect(response).to have_http_status(:ok)
    response.parsed_body.fetch('payload')
  end

  describe 'CA-2.3: campanha da página no filtro de campanha do CRM' do
    let(:usa_source_id) { 'site:ABC234:120211' }
    let(:europe_source_id) { 'site:ABC234:120299' }
    let!(:conversations) do
      page_signal(token: 'K7P2M9QX', params: campaign_params('120211', 'Viagem EUA'))
      page_signal(token: 'W3XY4Z5A', params: campaign_params('120211', 'Viagem EUA'))
      page_signal(token: 'P4QR5ST6', params: campaign_params('120299', 'Europa 60+'))
      {
        usa_first: whatsapp_message(wa_id: '5511911110001', text: 'Quero cotar seguro viagem para EUA #K7P2M9QX'),
        usa_second: whatsapp_message(wa_id: '5511911110002', text: 'Cotação EUA #W3XY4Z5A'),
        europe: whatsapp_message(wa_id: '5511911110003', text: 'Cotação Europa #P4QR5ST6')
      }
    end
    let!(:cards) { conversations.transform_values { |conversation| card_for(conversation) } }

    it 'atribuiu cada conversa ao toque estável da sua campanha' do
      expect(conversations.transform_values { |conversation| conversation.reload.additional_attributes['campaign_source_ids'] })
        .to eq(usa_first: [usa_source_id], usa_second: [usa_source_id], europe: [europe_source_id])
    end

    it 'o endpoint de opções devolve uma opção por campanha da página, não por clique, com "origem · campanha"' do
      options = get_ok('/ctwa_campaigns')

      expect(options.map { |option| option.except('last_touch_at') }).to eq(
        [
          { 'source_id' => usa_source_id, 'source' => 'meta_paid', 'headline' => 'LP Seguro Viagem · Viagem EUA', 'count' => 2 },
          { 'source_id' => europe_source_id, 'source' => 'meta_paid', 'headline' => 'LP Seguro Viagem · Europa 60+', 'count' => 1 }
        ]
      )
      expect(options.pluck('last_touch_at')).to all(be_present)
      expect(Ctwa::TrackedLinkClick.where(tracked_link: tracked_link).count).to eq(3)
    end

    it 'filtrar a lista de cards pela campanha devolve só os cards dela' do
      europe_ids = get_ok('/crm/cards', campaign_source_ids: europe_source_id).pluck('id')
      usa_ids = get_ok('/crm/cards', campaign_source_ids: usa_source_id).pluck('id')

      expect(europe_ids).to eq([cards[:europe].id])
      expect(usa_ids).to contain_exactly(cards[:usa_first].id, cards[:usa_second].id)
    end

    it 'filtrar o board pela campanha devolve só o card dela' do
      board = get_ok('/crm/kanban', pipeline_id: pipeline_and_stage.first.id, campaign_source_ids: europe_source_id)

      expect(board.fetch('stages').flat_map { |stage| stage['cards'] }.pluck('id')).to eq([cards[:europe].id])
    end
  end

  describe 'CA-2.2: texto editado pelo cliente não vence o formulário' do
    it 'lead_form da conversa e do card vêm do formulário da página, mesmo com outro destino no texto' do
      page_signal(token: 'K7P2M9QX', params: campaign_params('120211', 'Viagem EUA'))
      conversation = whatsapp_message(
        wa_id: '5511911110009',
        text: "Quero cotar seguro viagem para a Europa, 2 pessoas de 35 anos\nCódigo da cotação: #K7P2M9QX"
      )
      card = card_for(conversation)

      expect(conversation.messages.incoming.sole.content).to include('Europa')
      expected_form = { 'link_code' => 'ABC234', 'fields' => usa_fields }
      expect(conversation.reload.additional_attributes['lead_form']).to include(expected_form)
      expect(conversation.additional_attributes['campaign']).not_to have_key('inferred')
      expect(get_ok("/crm/cards/#{card.id}").fetch('lead_form')).to include(expected_form)
    end
  end
end

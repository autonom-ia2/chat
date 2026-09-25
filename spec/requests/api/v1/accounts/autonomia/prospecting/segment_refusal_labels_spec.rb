require 'rails_helper'

# Recusa depois do segmento (#732, revisão da E8): as duas campanhas leem o público pela etiqueta do segmento, a de
# envio único no disparo (tagged_with) e a da API do WhatsApp ao começar (AudienceResolver). Quem é descartado ou marcado
# como recusado depois de receber a etiqueta perde a etiqueta na hora, sem esperar alguém refazer o segmento. O contato
# que outro lead elegível da lista ainda alcança fica com ela.
RSpec.describe 'Autonomia prospecting refusal after segment', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/autonomia/prospecting" }
  let(:inbox) { create_whatsapp_api_inbox(account: account) }
  let(:campaign) do
    create_whatsapp_api_campaign(account: account, user: admin, inbox: inbox, label: account.labels.create!(title: 'base'))
  end
  let(:list) { Autonomia::Prospecting::List.create!(account: account, user: admin, name: 'Selecao') }

  around do |example|
    with_modified_env('WHATSAPP_API_CAMPAIGNS_ENABLED' => 'true') { example.run }
  end

  before { Autonomia::Prospecting::Config.enable_for!(account) }

  def create_lead(name, phone, in_list: true)
    lead = Autonomia::Prospecting::Lead.create!(
      account: account, provider: 'mock', provider_place_id: "refusal-#{name}", name: name, phone: phone, country: 'BR',
      status: :ready_for_campaign, metadata: { 'whatsapp_verification' => { 'status' => 'verified', 'phone' => phone } }
    )
    list.list_leads.create!(account: account, lead: lead) if in_list
    lead
  end

  def generate_segment
    post "#{base_url}/lists/#{list.id}/campaign_segment",
         params: { campaign_segment: { campaign_id: campaign.id, campaign_type: 'whatsapp_api', segment_name: 'Selecao' } },
         headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:created)
    response.parsed_body.dig('payload', 'segment', 'label', 'title')
  end

  def recipients_names
    WhatsappApiCampaigns::AudienceResolver.new(campaign.reload).perform
    campaign.whatsapp_api_campaign_recipients.map { |recipient| recipient.contact.name }
  end

  def one_off_audience(label_title)
    account.contacts.tagged_with([label_title], any: true).map(&:name)
  end

  it 'PATCH para recusado tira a etiqueta e o lead não entra no público das duas campanhas' do
    create_lead('Pronto', '+5531999990001')
    refused = create_lead('Depois recusou', '+5531999990002')
    label_title = generate_segment

    patch "#{base_url}/leads/#{refused.id}", params: { lead: { status: 'no_consent' } }, headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:ok)
    expect(refused.reload.contact.label_list).not_to include(label_title)
    expect(one_off_audience(label_title)).to eq(['Pronto'])
    expect(recipients_names).to eq(['Pronto'])
  end

  it 'PATCH para descartado tira a etiqueta' do
    create_lead('Pronto', '+5531999990001')
    discarded = create_lead('Descartado', '+5531999990002')
    label_title = generate_segment

    patch "#{base_url}/leads/#{discarded.id}", params: { lead: { status: 'discarded', discard_reason: 'Sem interesse' } },
                                               headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:ok)
    expect(discarded.reload.contact.label_list).not_to include(label_title)
  end

  it 'descarte em lote depois do segmento tira a etiqueta de todos os descartados' do
    create_lead('Pronto', '+5531999990001')
    first = create_lead('Descartado 1', '+5531999990002')
    second = create_lead('Descartado 2', '+5531999990003')
    label_title = generate_segment

    post "#{base_url}/leads/discard", params: { lead_ids: [first.id, second.id], reason: 'Sem interesse' },
                                      headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:ok)
    expect(one_off_audience(label_title)).to eq(['Pronto'])
    expect(recipients_names).to eq(['Pronto'])
  end

  it 'o contato que outro lead elegível da lista ainda alcança fica com a etiqueta' do
    create_lead('Pronto', '+5531999990001')
    duplicate = create_lead('Mesmo numero', '+5531999990001')
    label_title = generate_segment

    post "#{base_url}/leads/discard", params: { lead_ids: [duplicate.id], reason: 'Duplicado' }, headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:ok)
    expect(duplicate.reload.contact.label_list).to include(label_title)
  end

  it 'recusa de um lead fora da lista, pelo mesmo número, tira a etiqueta do contato da lista' do
    in_list = create_lead('Na lista', '+5531999990001')
    label_title = generate_segment
    outside = create_lead('Outra unidade', '+5531999990001', in_list: false)

    patch "#{base_url}/leads/#{outside.id}", params: { lead: { status: 'no_consent' } }, headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:ok)
    expect(in_list.reload.contact.label_list).not_to include(label_title)
    expect(recipients_names).to eq([])
  end

  it 'mudança que não é recusa não mexe na etiqueta' do
    lead = create_lead('Pronto', '+5531999990001')
    label_title = generate_segment

    patch "#{base_url}/leads/#{lead.id}", params: { lead: { status: 'qualified' } }, headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:ok)
    expect(lead.reload.contact.label_list).to include(label_title)
  end
end
